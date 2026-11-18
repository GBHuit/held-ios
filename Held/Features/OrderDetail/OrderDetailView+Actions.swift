import Foundation
import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

private enum OrderDetailActionError: LocalizedError {
    case save(String, String)
    case missingPhoto
    case cleanup(String)

    var errorDescription: String? {
        switch self {
        case .save(let action, let reason):
            return L("%1$@ could not be saved. %2$@", action, reason)
        case .missingPhoto:
            return L("The selected photo could not be read. Choose it again or import the original file instead.")
        case .cleanup(let reason):
            return reason
        }
    }
}

// MARK: - Storage and scalar updates

extension OrderDetailView {
    func prepareAttachmentStore() async {
        guard attachmentStore == nil else { return }
        do {
            attachmentStore = try AttachmentStore()
            storageError = nil
        } catch {
            storageError = error.localizedDescription
        }
    }

    func saveContext(action: String) throws {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw OrderDetailActionError.save(action, error.localizedDescription)
        }
    }

    func currentSettings() throws -> AppSettings {
        if let settings = settings.first { return settings }
        let created = try AppSettings.fetchOrCreate(context: modelContext)
        try saveContext(action: L("Settings"))
        return created
    }

    func updateFulfillmentStatus(_ newValue: FulfillmentStatus) {
        if newValue == .delivered && !allNoncancelledItemsAreDelivered {
            errorMessage = OrderDetailValidationError.incompleteDelivery.localizedDescription
            return
        }
        order.fulfillmentStatus = newValue
        order.lastUserUpdateAt = Date()
        do {
            try saveContext(action: L("Fulfillment status"))
            synchronizeReminders()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateResolutionStatus(_ newValue: ResolutionStatus) {
        order.resolutionStatus = newValue
        order.lastUserUpdateAt = Date()
        do {
            try saveContext(action: L("Resolution status"))
            synchronizeReminders()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applyOrderEdit(_ draft: OrderEditDraft) throws {
        let title = try OrderDetailValidation.require(draft.title, field: L("Order title"))
        let amountMinor = try OrderDetailValidation.minorUnits(from: draft.amountText)
        let paymentMethod = try OrderDetailValidation.paymentMethod(draft.paymentMethod)
        let sourceURL = try OrderDetailValidation.optionalURL(draft.sourceURL)
        let previousStart = order.estimateStart
        let previousEnd = order.estimateEnd
        let previousPrecision = order.estimatePrecision
        let previousNextCheck = order.nextCheckAt

        order.title = title
        order.vendor = OrderDetailValidation.trimmed(draft.vendor)
        order.orderNumber = OrderDetailValidation.trimmed(draft.orderNumber)
        order.orderedAt = draft.orderedAt
        order.amountMinor = amountMinor
        order.currencyCode = draft.currencyCode
        order.paymentMethod = paymentMethod
        order.sourceURL = sourceURL
        order.estimateStart = draft.estimateStart
        order.estimateEnd = draft.estimateEnd
        order.estimatePrecision = draft.estimatePrecision
        order.nextCheckAt = draft.nextCheckAt
        order.lastUserUpdateAt = Date()

        // estimateText and every existing Evidence value deliberately remain untouched.
        if previousStart != draft.estimateStart || previousEnd != draft.estimateEnd || previousPrecision != draft.estimatePrecision {
            let isDelay: Bool
            if let previousEnd, let revised = draft.estimateEnd {
                isDelay = revised > previousEnd
            } else {
                isDelay = false
            }
            var note = L("Previous estimate: %@\n", localizedEstimateText(precision: previousPrecision, start: previousStart, end: previousEnd))
            note += L("Revised estimate: %@.", localizedEstimateText(precision: draft.estimatePrecision, start: draft.estimateStart, end: draft.estimateEnd))
            if !order.estimateText.isEmpty {
                note += L("\nOriginal estimate preserved: %@", order.estimateText)
            }
            let revisionNote = OrderDetailValidation.trimmed(draft.estimateRevisionNote)
            if !revisionNote.isEmpty { note += "\n\(revisionNote)" }

            let milestone = Milestone(
                kind: isDelay ? .delay : .update,
                occurredAt: Date(),
                title: L("Delivery estimate revised"),
                note: note,
                sourceURL: sourceURL.isEmpty ? nil : sourceURL,
                order: order
            )
            modelContext.insert(milestone)
            order.milestones.append(milestone)
        }

        if previousNextCheck != draft.nextCheckAt {
            synchronizeCheckInReminder(from: previousNextCheck, to: draft.nextCheckAt)
        }

        try saveContext(action: L("Order changes"))
        synchronizeReminders(requestAuthorization: previousNextCheck != draft.nextCheckAt)
    }

    private func synchronizeCheckInReminder(from previousDate: Date?, to newDate: Date?) {
        let checkIns = order.reminders.filter { $0.kind == .checkIn }
        if let newDate {
            let linked = checkIns.first { $0.triggerAt == previousDate }
                ?? (checkIns.count == 1 ? checkIns[0] : nil)
            if let linked {
                linked.triggerAt = newDate
            } else {
                let reminder = HeldReminder(
                    kind: .checkIn,
                    triggerAt: newDate,
                    leadDays: 0,
                    enabled: true,
                    label: L("Check in with %@", order.vendor),
                    order: order
                )
                modelContext.insert(reminder)
                order.reminders.append(reminder)
            }
        } else if let previousDate {
            for reminder in checkIns where reminder.triggerAt == previousDate {
                reminder.enabled = false
            }
        }
    }

    func applyNotesUpdate(_ draft: OrderNotesDraft) throws {
        order.notes = OrderDetailValidation.trimmed(draft.notes)
        order.trackingNumber = OrderDetailValidation.trimmed(draft.trackingNumber)
        order.carrier = OrderDetailValidation.trimmed(draft.carrier)
        order.lastUserUpdateAt = Date()
        try saveContext(action: L("Notes and tracking"))
    }
}

// MARK: - Delivery derivation

extension OrderDetailView {
    var allNoncancelledItemsAreDelivered: Bool {
        guard !order.items.isEmpty else { return true }
        let items = order.items.filter { $0.status != .cancelled && $0.quantity > 0 }
        return !items.isEmpty && items.allSatisfy {
            $0.status == .delivered && $0.deliveredQuantity >= $0.quantity
        }
    }

    func applyDeliveryUpdate(_ drafts: [OrderItemDeliveryDraft]) throws {
        let draftsByID = Dictionary(drafts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for item in order.items {
            guard let draft = draftsByID[item.id] else { continue }
            let quantity = max(0, item.quantity)
            item.deliveredQuantity = min(quantity, max(0, draft.deliveredQuantity))
            item.status = draft.status
            if item.status == .delivered {
                item.deliveredQuantity = quantity
            }
        }

        let noncancelled = order.items.filter { $0.status != .cancelled && $0.quantity > 0 }
        let allDelivered = order.items.isEmpty || (!noncancelled.isEmpty && noncancelled.allSatisfy {
            $0.status == .delivered && $0.deliveredQuantity >= $0.quantity
        })
        let hasPartialProgress = order.items.contains {
            guard $0.status != .cancelled && $0.status != .refunded else { return false }
            return $0.deliveredQuantity > 0 || $0.status == .shipped || $0.status == .delivered
        }

        if allDelivered {
            order.fulfillmentStatus = .delivered
        } else if hasPartialProgress {
            order.fulfillmentStatus = .partiallyShipped
        } else if order.fulfillmentStatus == .delivered || order.fulfillmentStatus == .partiallyShipped {
            // Never leave a false completed or partial state after quantities are reduced.
            order.fulfillmentStatus = .ordered
        }

        order.lastUserUpdateAt = Date()
        try saveContext(action: L("Delivery update"))
        synchronizeReminders()
    }
}

// MARK: - Milestones and reminders

extension OrderDetailView {
    func addMilestone(_ draft: MilestoneDraft) throws {
        let title = try OrderDetailValidation.require(draft.title, field: L("Milestone title"))
        let source = try OrderDetailValidation.optionalURL(draft.sourceURL)
        let milestone = Milestone(
            kind: draft.kind,
            occurredAt: draft.occurredAt,
            title: title,
            note: OrderDetailValidation.trimmed(draft.note),
            sourceURL: source.isEmpty ? nil : source,
            order: order
        )
        modelContext.insert(milestone)
        order.milestones.append(milestone)
        order.lastUserUpdateAt = Date()
        try saveContext(action: L("Milestone"))
    }

    func addReminder(_ draft: ReminderDraft) throws {
        let label = try OrderDetailValidation.require(draft.label, field: L("Reminder label"))
        let triggerAt = draft.triggerAt
        guard draft.notificationAt > Date() else {
            throw OrderDetailValidationError.invalidReminderDate
        }
        let reminder = HeldReminder(
            kind: draft.kind,
            triggerAt: triggerAt,
            leadDays: min(365, max(0, draft.leadDays)),
            enabled: true,
            label: label,
            order: order
        )
        modelContext.insert(reminder)
        order.reminders.append(reminder)
        order.lastUserUpdateAt = Date()
        try saveContext(action: L("Reminder"))
        synchronizeReminders(requestAuthorization: true)
    }

    func updateReminder(_ reminder: HeldReminder, enabled: Bool) {
        reminder.enabled = enabled
        order.lastUserUpdateAt = Date()
        do {
            try saveContext(action: L("Reminder"))
            synchronizeReminders(requestAuthorization: enabled)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func requestNotificationAuthorization() {
        Task {
            if reminderScheduler.authorizationStatus == .notDetermined {
                _ = await reminderScheduler.requestAuthorization()
            }
            synchronizeReminders()
        }
    }

    func synchronizeReminders(requestAuthorization: Bool = false) {
        Task {
            do {
                let orders = try modelContext.fetch(FetchDescriptor<HeldOrder>())
                let currentSettings = try currentSettings()
                if requestAuthorization && currentSettings.remindersEnabled,
                   reminderScheduler.authorizationStatus == .notDetermined {
                    _ = await reminderScheduler.requestAuthorization()
                }
                await reminderScheduler.sync(orders: orders, settings: currentSettings)
                if let schedulerError = reminderScheduler.lastErrorMessage {
                    errorMessage = L(schedulerError)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Evidence import, save, and deletion

extension OrderDetailView {
    func importSelectedFile(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            guard let attachmentStore else {
                throw OrderDetailValidationError.attachmentStoreUnavailable
            }
            let metadata = try attachmentStore.importFile(from: url)
            var draft = EvidenceDraft()
            draft.title = URL(fileURLWithPath: metadata.filename).deletingPathExtension().lastPathComponent
            draft.source = L("Imported file")
            draft.attachment = metadata
            activeSheet = .evidence(draft)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importSelectedPhoto(_ item: PhotosPickerItem) {
        guard let attachmentStore else {
            errorMessage = OrderDetailValidationError.attachmentStoreUnavailable.localizedDescription
            selectedPhoto = nil
            return
        }
        isWorking = true
        Task {
            defer {
                isWorking = false
                selectedPhoto = nil
            }
            do {
                guard let data = try await item.loadTransferable(type: Data.self), !data.isEmpty else {
                    throw OrderDetailActionError.missingPhoto
                }
                let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(ext)
                try data.write(to: tempURL)
                defer { try? FileManager.default.removeItem(at: tempURL) }
                let metadata = try attachmentStore.importFile(from: tempURL)
                var draft = EvidenceDraft()
                draft.title = URL(fileURLWithPath: metadata.filename).deletingPathExtension().lastPathComponent
                draft.source = L("Imported photo")
                draft.attachment = metadata
                activeSheet = .evidence(draft)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func saveEvidence(_ draft: EvidenceDraft) throws {
        let title = try OrderDetailValidation.require(draft.title, field: L("Evidence title"))
        let filename: String
        if let attachment = draft.attachment {
            filename = attachment.filename
        } else {
            filename = try OrderDetailValidation.require(draft.referenceFilename, field: L("Reference filename"))
        }

        let evidence = Evidence(
            kind: draft.kind,
            title: title,
            filename: filename,
            capturedAt: draft.capturedAt,
            source: OrderDetailValidation.trimmed(draft.source),
            note: OrderDetailValidation.trimmed(draft.note),
            localRelativePath: draft.attachment?.relativePath,
            mimeType: draft.attachment?.mimeType ?? "",
            fileSize: draft.attachment?.fileSize ?? 0,
            sha256: draft.attachment?.sha256,
            order: order
        )
        modelContext.insert(evidence)
        order.evidence.append(evidence)
        order.lastUserUpdateAt = Date()
        try saveContext(action: L("Evidence"))
    }

    func cancelEvidenceImport(_ draft: EvidenceDraft) {
        guard let path = draft.attachment?.relativePath else { return }
        do {
            guard let attachmentStore else {
                throw OrderDetailValidationError.attachmentStoreUnavailable
            }
            try attachmentStore.remove(relativePath: path)
        } catch {
            errorMessage = L("The import was cancelled, but its temporary attachment could not be removed: %@", error.localizedDescription)
        }
    }

    func deleteEvidence(_ evidence: Evidence) throws {
        let path = evidence.localRelativePath
        modelContext.delete(evidence)
        order.lastUserUpdateAt = Date()
        try saveContext(action: L("Evidence deletion"))

        guard let path else { return }
        do {
            guard let attachmentStore else {
                throw OrderDetailValidationError.attachmentStoreUnavailable
            }
            try attachmentStore.remove(relativePath: path)
        } catch {
            throw OrderDetailActionError.cleanup(
                L("The evidence metadata was deleted, but its attachment could not be removed: %@", error.localizedDescription)
            )
        }
    }
}

// MARK: - Single-order export

extension OrderDetailView {
    func prepareExport(_ kind: OrderExportKind) {
        isWorking = true
        defer { isWorking = false }

        do {
            let service = ExportService()
            let url: URL
            switch kind {
            case .json:
                let data = try service.encodeJSON(orders: [order], settings: currentSettings())
                url = FileManager.default.temporaryDirectory
                    .appendingPathComponent(orderDetailFilename(for: order, kind: kind))
                try data.write(to: url, options: .atomic)
            case .csv:
                url = try service.writeCSV(orders: [order])
            case .pdf:
                url = try service.writeEvidenceReport(orders: [order])
            case .evidenceZIP:
                guard let attachmentStore else {
                    throw OrderDetailValidationError.attachmentStoreUnavailable
                }
                url = try service.writeArchive(
                    orders: [order],
                    settings: currentSettings(),
                    attachmentStore: attachmentStore
                )
            }

            // Let the privacy sheet finish dismissing before presenting the activity controller.
            DispatchQueue.main.async {
                shareItem = OrderShareItem(url: url, kind: kind)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Order deletion

extension OrderDetailView {
    func deleteOrder() {
        let orderID = order.id
        let attachmentPaths = order.evidence.compactMap(\.localRelativePath)
        isWorking = true

        do {
            modelContext.delete(order)
            try saveContext(action: L("Order deletion"))
        } catch {
            isWorking = false
            errorMessage = error.localizedDescription
            return
        }

        Task {
            await reminderScheduler.cancel(orderID: orderID)

            var cleanupFailures = [String]()
            if attachmentPaths.isEmpty {
                // Nothing to clean up.
            } else if let attachmentStore {
                for path in attachmentPaths {
                    do {
                        try attachmentStore.remove(relativePath: path)
                    } catch {
                        cleanupFailures.append("\(path): \(error.localizedDescription)")
                    }
                }
            } else {
                cleanupFailures.append(L("Attachment storage was unavailable; imported files may remain on device."))
            }

            isWorking = false
            if cleanupFailures.isEmpty {
                dismiss()
            } else {
                deletionCleanupWarning = L("The order and its notifications were deleted. Some attachment files could not be removed:\n\n%@", cleanupFailures.joined(separator: "\n"))
            }
        }
    }
}
