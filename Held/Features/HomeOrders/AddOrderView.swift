import SwiftUI
import SwiftData
import PhotosUI
import UIKit

private enum AddOrderStep: Int, CaseIterable {
    case basics
    case promise
    case itemsAndReminder

    var title: String {
        switch self {
        case .basics: return L("Basics")
        case .promise: return L("Promise")
        case .itemsAndReminder: return L("Items & reminder")
        }
    }
}

private struct AddOrderItemDraft: Identifiable {
    let id = UUID()
    var name = ""
    var variant = ""
    var quantityText = "1"
    var amountText = ""
}

private struct AddOrderInputError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

struct AddOrderView: View {
    @EnvironmentObject private var localization: LocalizationCenter
    let pendingShare: PendingShare?

    @Query private var orders: [HeldOrder]
    @Query private var settings: [AppSettings]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var reminderScheduler: ReminderScheduler
    @EnvironmentObject private var purchaseService: PurchaseService

    @State private var step: AddOrderStep = .basics
    @State private var showingProUpgrade = false

    @State private var title = ""
    @State private var vendor = ""
    @State private var orderNumber = ""
    @State private var orderDate = Date()
    @State private var amountText = ""
    @State private var currency: CurrencyCode = .USD
    @State private var paymentMethod = ""
    @State private var sourceURL = ""

    @State private var estimateText = ""
    @State private var estimatePrecision: EstimatePrecision = .unknown
    @State private var estimateStart = Date()
    @State private var estimateEnd = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    @State private var estimateReferenceDate = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    @State private var trackingNumber = ""
    @State private var carrier = ""

    @State private var itemDrafts: [AddOrderItemDraft] = []
    @State private var nextCheckEnabled = true
    @State private var nextCheckAt = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var deadlineReminderEnabled = false
    @State private var deadlineReminderAt = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
    @State private var deadlineLeadDays = 7

    @State private var validationMessage: String?
    @State private var isSaving = false
    @State private var didLoadReminderSettings = false
    @State private var didApplyPendingShare = false

    // MARK: Shared-share prefill and OCR intake
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingDocumentScanner = false
    @State private var isRecognizing = false
    @State private var ocrResult: OCRResult?
    @State private var ocrReviewImages: [OCRReviewedImage] = []
    @State private var reviewedReceiptImages: [OCRReviewedImage] = []
    @State private var ocrStatusMessage: String?

    init(pendingShare: PendingShare? = nil) {
        self.pendingShare = pendingShare
    }

    private var ocrReviewPresented: Binding<Bool> {
        Binding(
            get: { ocrResult != nil },
            set: { if !$0 { cancelOCRReview() } }
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progressIndicator
                    .padding(.horizontal, HeldSpacing.medium)
                    .padding(.vertical, HeldSpacing.medium)
                    .background(HeldColor.background)

                Form {
                    if isAtActiveOrderLimit {
                        orderLimitSection
                    }

                    switch step {
                    case .basics:
                        basicsSection
                    case .promise:
                        promiseSection
                    case .itemsAndReminder:
                        itemsAndReminderSection
                    }
                }
                .scrollContentBackground(.hidden)
                .background(HeldColor.background)
                .scrollDismissesKeyboard(.interactively)
            }
            .heldScreenBackground()
            .navigationTitle(L("New order"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel"), action: cancelNewOrder)
                        .disabled(isSaving)
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomControls
            }
            .interactiveDismissDisabled(isSaving)
            .heldLoadingOverlay(isPresented: isSaving, title: L("Saving your order…"))
            .sheet(isPresented: ocrReviewPresented) {
                if let ocrResult {
                    OCRReviewView(
                        result: ocrResult,
                        canKeepReceipt: !ocrReviewImages.isEmpty,
                        onApply: applyOCRSuggestions,
                        onCancel: cancelOCRReview
                    )
                }
            }
            .sheet(isPresented: $showingDocumentScanner) {
                DocumentCameraScanner(
                    onComplete: { images in
                        showingDocumentScanner = false
                        Task { await recognizeScannedImages(images) }
                    },
                    onCancel: { showingDocumentScanner = false },
                    onError: { message in
                        showingDocumentScanner = false
                        ocrStatusMessage = message
                    }
                )
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showingProUpgrade) {
                proUpgradeSheet
            }
            .onChange(of: selectedPhoto) { _, newValue in
                guard let newValue else { return }
                Task { await recognizePhoto(newValue) }
            }
            .task {
                applyPendingShareIfNeeded()
                ensureSettingsExist()
            }
        }
    }

    private var isProUnlocked: Bool {
        purchaseService.isPro || settings.contains(where: \.proUnlocked)
    }

    private var isAtActiveOrderLimit: Bool {
        !isProUnlocked && orders.filter(\.isActive).count >= 3
    }

    private var orderLimitSection: some View {
        Section {
            Label(L("Free includes up to 3 active orders"), systemImage: "shippingbox")
                .font(.headline)
                .foregroundStyle(HeldColor.accent)
            Text(L("This new order would be a fourth active order. Upgrade to Keyvow Pro for unlimited active orders, or resolve an existing order before saving. Delivered, cancelled, and fully refunded orders do not count toward the limit."))
                .heldBody()
                .foregroundStyle(HeldColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Button(L("View Keyvow Pro upgrade")) {
                showingProUpgrade = true
            }
            .heldButtonStyle(.primary)
        }
    }

    private var proUpgradeSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HeldSpacing.large) {
                    VStack(alignment: .leading, spacing: HeldSpacing.small) {
                        Text(L("Keep every order in view."))
                            .heldDisplay(size: 30)
                            .foregroundStyle(HeldColor.ink)
                        Text(L("Keyvow Pro is a one-time lifetime upgrade with unlimited active orders. The free version keeps up to 3 active orders; your existing orders, evidence, exports, and backups remain available."))
                            .heldBody()
                            .foregroundStyle(HeldColor.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if purchaseService.isLoading {
                        HStack(spacing: HeldSpacing.small) {
                            ProgressView()
                            Text(L("Contacting the App Store…"))
                                .foregroundStyle(HeldColor.secondaryInk)
                        }
                    }

                    if let price = purchaseService.displayPrice {
                        Button(L("Get Keyvow Pro — %@", price), action: purchasePro)
                            .heldButtonStyle(.primary)
                            .disabled(purchaseService.isLoading)
                    } else if !purchaseService.isLoading {
                        VStack(alignment: .leading, spacing: HeldSpacing.small) {
                            Text(L("Keyvow Pro is not available for purchase right now. Your orders, evidence, exports, and backups remain fully available."))
                                .heldBody()
                                .foregroundStyle(HeldColor.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                            Button(L("Check App Store availability again")) {
                                Task { @MainActor in
                                    await purchaseService.loadProduct()
                                }
                            }
                            .heldButtonStyle(.secondary)
                        }
                    }

                    Button(L("Restore Purchases"), action: restorePro)
                        .heldButtonStyle(.quiet)
                        .disabled(purchaseService.isLoading)

                    if let status = purchaseService.statusMessage {
                        Label(L(status), systemImage: "info.circle")
                            .heldCaption()
                            .foregroundStyle(HeldColor.accent)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let error = purchaseService.errorMessage {
                        Label(L(error), systemImage: "exclamationmark.triangle")
                            .heldCaption()
                            .foregroundStyle(HeldColor.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(HeldSpacing.large)
            }
            .heldScreenBackground()
            .navigationTitle(L("Keyvow Pro"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Not now")) { showingProUpgrade = false }
                        .disabled(purchaseService.isLoading)
                }
            }
            .task {
                if !purchaseService.isAvailable && !purchaseService.isLoading {
                    await purchaseService.loadProduct()
                }
            }
        }
    }

    private func purchasePro() {
        Task { @MainActor in
            do {
                let appSettings = try AppSettings.fetchOrCreate(context: modelContext)
                let unlocked = await purchaseService.purchase(settings: appSettings)
                try modelContext.save()
                if unlocked {
                    validationMessage = nil
                    showingProUpgrade = false
                }
            } catch {
                validationMessage = L("The upgrade could not be saved. Please try again.")
            }
        }
    }

    private func restorePro() {
        Task { @MainActor in
            do {
                let appSettings = try AppSettings.fetchOrCreate(context: modelContext)
                let unlocked = await purchaseService.restorePurchases(settings: appSettings)
                try modelContext.save()
                if unlocked {
                    validationMessage = nil
                    showingProUpgrade = false
                }
            } catch {
                validationMessage = L("The restored purchase could not be saved. Please try again.")
            }
        }
    }

    private var progressIndicator: some View {
        VStack(alignment: .leading, spacing: HeldSpacing.small) {
            HStack(spacing: HeldSpacing.small) {
                ForEach(AddOrderStep.allCases, id: \.rawValue) { item in
                    Capsule()
                        .fill(item.rawValue <= step.rawValue ? HeldColor.accent : HeldColor.separator)
                        .frame(height: 4)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)

            Text(L("%1$@ — Step %2$lld of %3$lld", step.title, step.rawValue + 1, AddOrderStep.allCases.count))
                .heldCaption()
                .foregroundStyle(HeldColor.secondaryInk)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Step %1$lld of %2$lld: %3$@", step.rawValue + 1, AddOrderStep.allCases.count, step.title))
    }

    @ViewBuilder
    private var basicsSection: some View {
        Section {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label(L("Choose a receipt or confirmation"), systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 44)
            }
            .disabled(isRecognizing)

            if DocumentCameraScanner.isSupported {
                Button {
                    showingDocumentScanner = true
                } label: {
                    Label(L("Scan with camera"), systemImage: "doc.text.viewfinder")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 44)
                }
                .disabled(isRecognizing)
            }

            if isRecognizing {
                HStack(spacing: HeldSpacing.small) {
                    ProgressView()
                    Text(L("Looking for order details…"))
                        .foregroundStyle(HeldColor.secondaryInk)
                }
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)
            }

            Text(L("OCR suggestions need your confirmation. Nothing is added to the form until you review them."))
                .heldCaption()
                .foregroundStyle(HeldColor.secondaryInk)

            if !reviewedReceiptImages.isEmpty {
                Label(L("Reviewed receipt image ready to save as evidence"), systemImage: "checkmark.circle")
                    .heldCaption()
                    .foregroundStyle(HeldColor.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let ocrStatusMessage {
                Text(L(ocrStatusMessage))
                    .heldCaption()
                    .foregroundStyle(HeldColor.secondaryInk)
            }
        } header: {
            Text(L("Start with a photo or scan — optional"))
        } footer: {
            Text(L("No image? Continue with the manual fields below. Camera scans and selected photos both open OCR review before changing any field."))
        }

        Section {
            TextField(L("Order title"), text: $title, axis: .vertical)
                .textInputAutocapitalization(.words)
            TextField(L("Vendor"), text: $vendor)
                .textInputAutocapitalization(.words)
            TextField(L("Order number — optional"), text: $orderNumber)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            DatePicker(L("Order date"), selection: $orderDate, displayedComponents: .date)
        } header: {
            Text(L("The essentials"))
        } footer: {
            Text(L("Title and vendor are required."))
        }

        Section {
            TextField(L("Amount — for example, 249.00"), text: $amountText)
                .keyboardType(.decimalPad)
            Picker(L("Currency"), selection: $currency) {
                ForEach(CurrencyCode.allCases, id: \.self) { code in
                    Text(code.rawValue).tag(code)
                }
            }
            TextField(L("Payment method — optional"), text: $paymentMethod)
            TextField(L("Order or listing URL — optional"), text: $sourceURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text(L("Payment"))
        } footer: {
            Text(L("Leave the amount blank if it is not known yet. Use at most two decimal places. For payment, enter only the method and optional last four digits; never enter a full card number."))
        }
    }

    @ViewBuilder
    private var promiseSection: some View {
        Section {
            TextField(
                L("Original estimate — for example, “Ships in 8–10 weeks”"),
                text: $estimateText,
                axis: .vertical
            )
            .lineLimit(3...7)

            Picker(L("Estimate precision"), selection: $estimatePrecision) {
                ForEach(EstimatePrecision.allCases, id: \.self) { precision in
                    Text(localizedEstimatePrecisionLabel(precision)).tag(precision)
                }
            }

            switch estimatePrecision {
            case .unknown:
                Text(L("No estimated dates will be stored. You can keep only the original wording above."))
                    .heldCaption()
                    .foregroundStyle(HeldColor.secondaryInk)
            case .day:
                DatePicker(L("Estimated start"), selection: $estimateStart, displayedComponents: .date)
                DatePicker(L("Estimated end"), selection: $estimateEnd, displayedComponents: .date)
            case .month:
                DatePicker(L("Any date in the estimated month"), selection: $estimateReferenceDate, displayedComponents: .date)
            case .quarter:
                DatePicker(L("Any date in the estimated quarter"), selection: $estimateReferenceDate, displayedComponents: .date)
            case .season:
                DatePicker(L("Any date in the estimated season"), selection: $estimateReferenceDate, displayedComponents: .date)
                Text(L("Seasons use meteorological boundaries: March–May, June–August, September–November, and December–February."))
                    .heldCaption()
                    .foregroundStyle(HeldColor.secondaryInk)
            }

            if estimatePrecision != .unknown {
                let range = DeliveryEstimate.resolve(
                    precision: estimatePrecision,
                    start: estimateStart,
                    end: estimateEnd,
                    referenceDate: estimateReferenceDate
                )
                Text(L("Saved as: %@", localizedEstimateText(precision: estimatePrecision, start: range.start, end: range.end)))
                    .heldCaption()
                    .foregroundStyle(HeldColor.accent)
            }
        } header: {
            Text(L("The original promise"))
        } footer: {
            Text(L("Keyvow saves this wording with the purchase milestone. Later updates will not rewrite the original promise. Approximate estimates use the end of their range for attention, not a fake exact-day promise."))
        }

        Section {
            TextField(L("Tracking number — optional"), text: $trackingNumber)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField(L("Carrier — optional"), text: $carrier)
        } header: {
            Text(L("Shipping — optional"))
        }
    }

    @ViewBuilder
    private var itemsAndReminderSection: some View {
        Section {
            if itemDrafts.isEmpty {
                Text(L("No line items yet. You can save without them, or add the items that make up this order."))
                    .heldBody()
                    .foregroundStyle(HeldColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach($itemDrafts) { $item in
                VStack(alignment: .leading, spacing: HeldSpacing.small) {
                    HStack {
                        Text(L("Item"))
                            .font(.headline)
                        Spacer()
                        Button(L("Remove"), role: .destructive) {
                            itemDrafts.removeAll { $0.id == item.id }
                        }
                        .font(.subheadline)
                        .frame(minWidth: 44, minHeight: 44)
                    }

                    TextField(L("Item name"), text: $item.name)
                    TextField(L("Variant — optional"), text: $item.variant)
                    TextField(L("Quantity"), text: $item.quantityText)
                        .keyboardType(.numberPad)
                    TextField(L("Line amount in %@ — optional", currency.rawValue), text: $item.amountText)
                        .keyboardType(.decimalPad)
                }
                .padding(.vertical, HeldSpacing.extraSmall)
            }

            Button {
                itemDrafts.append(AddOrderItemDraft())
            } label: {
                Label(L("Add an item"), systemImage: "plus")
                    .frame(minHeight: 44)
            }
        } header: {
            Text(L("Items — optional"))
        } footer: {
            Text(L("Each item needs a name and a quantity of at least 1. A line amount is the total for that line, not a unit price."))
        }

        Section {
            Toggle(L("Check in on this order"), isOn: $nextCheckEnabled)
            if nextCheckEnabled {
                DatePicker(
                    L("Next check-in"),
                    selection: $nextCheckAt,
                    displayedComponents: [.date, .hourAndMinute]
                )
            }

            Toggle(L("Add a deadline reminder"), isOn: $deadlineReminderEnabled)
            if deadlineReminderEnabled {
                DatePicker(
                    L("Reminder date"),
                    selection: $deadlineReminderAt,
                    displayedComponents: [.date, .hourAndMinute]
                )
                Stepper(deadlineLeadDays == 1 ? L("Lead time: %lld day", deadlineLeadDays) : L("Lead time: %lld days", deadlineLeadDays), value: $deadlineLeadDays, in: 0...90)
                Text(L("Keyvow organizes dates and documents. It does not determine dispute eligibility, file disputes, or guarantee recovery. Verify current rules with your payment provider."))
                    .heldCaption()
                    .foregroundStyle(HeldColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                if let informationURL = URL(string: HomeOrdersText.trimmed(sourceURL)),
                   let scheme = informationURL.scheme?.lowercased(),
                   ["http", "https"].contains(scheme) {
                    Link(L("Open the saved order or official information link"), destination: informationURL)
                        .heldCaption()
                }
            }
        } header: {
            Text(L("Reminders"))
        } footer: {
            Text(L("New orders include a check-in by default. Notifications follow your Keyvow settings; reminder dates are saved even when system notifications are off."))
        }
    }

    private var bottomControls: some View {
        VStack(spacing: HeldSpacing.small) {
            if let validationMessage {
                Text(L(validationMessage))
                    .heldCaption()
                    .foregroundStyle(HeldColor.danger)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.updatesFrequently)
            }

            HStack(spacing: HeldSpacing.medium) {
                if step != .basics {
                    Button(L("Back")) {
                        validationMessage = nil
                        step = AddOrderStep(rawValue: step.rawValue - 1) ?? .basics
                    }
                    .heldButtonStyle(.secondary)
                    .disabled(isSaving)
                }

                Spacer(minLength: 0)

                if step == .itemsAndReminder {
                    Button(L("Save order")) {
                        Task { await saveOrder() }
                    }
                    .heldButtonStyle()
                    .disabled(isSaving || isRecognizing)
                } else {
                    Button(L("Continue")) {
                        continueToNextStep()
                    }
                    .heldButtonStyle()
                    .disabled(isSaving)
                }
            }
        }
        .padding(.horizontal, HeldSpacing.medium)
        .padding(.vertical, HeldSpacing.small)
        .background(HeldColor.background.ignoresSafeArea(edges: .bottom))
    }

    private func continueToNextStep() {
        do {
            if step == .basics {
                try validateBasics()
            } else if step == .promise {
                try validateEstimate()
            }
            validationMessage = nil
            step = AddOrderStep(rawValue: step.rawValue + 1) ?? .itemsAndReminder
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func validateBasics() throws {
        guard !HomeOrdersText.trimmed(title).isEmpty else {
            throw AddOrderInputError(L("Enter an order title before continuing."))
        }
        guard !HomeOrdersText.trimmed(vendor).isEmpty else {
            throw AddOrderInputError(L("Enter the vendor before continuing."))
        }
        let trimmedURL = HomeOrdersText.trimmed(sourceURL)
        if !trimmedURL.isEmpty {
            guard let url = URL(string: trimmedURL),
                  let scheme = url.scheme?.lowercased(),
                  ["http", "https"].contains(scheme),
                  url.host != nil else {
                throw AddOrderInputError(L("Enter a complete http or https order URL, or leave the URL blank."))
            }
        }
        _ = try AddOrderMoney.minorUnits(from: amountText, fieldName: L("Order amount"))
        guard !containsFullCardNumber(paymentMethod) else {
            throw AddOrderInputError(L("For your security, enter only the payment method and optional last four digits. Full card numbers are never saved."))
        }
    }

    private func validateEstimate() throws {
        let range = DeliveryEstimate.resolve(
            precision: estimatePrecision,
            start: estimateStart,
            end: estimateEnd,
            referenceDate: estimateReferenceDate
        )
        guard range.isChronological else {
            throw AddOrderInputError(L("Estimated start must be on or before estimated end."))
        }
    }

    private func validateItems() throws {
        for (index, item) in itemDrafts.enumerated() {
            let itemNumber = index + 1
            guard !HomeOrdersText.trimmed(item.name).isEmpty else {
                throw AddOrderInputError(L("Enter a name for item %lld, or remove that item.", itemNumber))
            }
            guard let quantity = Int(HomeOrdersText.trimmed(item.quantityText)), quantity >= 1 else {
                throw AddOrderInputError(L("Item %lld needs a quantity of at least 1.", itemNumber))
            }
            _ = try AddOrderMoney.minorUnits(from: item.amountText, fieldName: L("Amount for item %lld", itemNumber))
        }
    }

    private func ensureSettingsExist() {
        if !didLoadReminderSettings {
            deadlineLeadDays = min(90, max(0, settings.first?.leadDays ?? 7))
            didLoadReminderSettings = true
        }
        guard settings.isEmpty else { return }
        do {
            _ = try AppSettings.fetchOrCreate(context: modelContext)
            try modelContext.save()
        } catch {
            // Saving the order will try again and report any persistent storage error.
        }
    }

    @MainActor
    private func saveOrder() async {
        guard !isAtActiveOrderLimit else {
            validationMessage = L("Free includes up to 3 active orders. Upgrade for unlimited active orders, or resolve an existing order before saving.")
            showingProUpgrade = true
            return
        }

        do {
            try validateBasics()
            try validateEstimate()
            try validateItems()
        } catch {
            validationMessage = error.localizedDescription
            return
        }

        validationMessage = nil
        isSaving = true
        defer { isSaving = false }
        var importedReceiptPaths: [String] = []
        var didPersistOrder = false

        do {
            let trimmedTitle = HomeOrdersText.trimmed(title)
            let trimmedVendor = HomeOrdersText.trimmed(vendor)
            let trimmedEstimate = HomeOrdersText.trimmed(estimateText)
            let trimmedSourceURL = HomeOrdersText.trimmed(sourceURL)
            let amountMinor = try AddOrderMoney.minorUnits(from: amountText, fieldName: L("Order amount")) ?? 0
            let estimateRange = DeliveryEstimate.resolve(
                precision: estimatePrecision,
                start: estimateStart,
                end: estimateEnd,
                referenceDate: estimateReferenceDate
            )

            let order = HeldOrder(
                title: trimmedTitle,
                vendor: trimmedVendor,
                orderNumber: HomeOrdersText.trimmed(orderNumber),
                orderedAt: orderDate,
                amountMinor: amountMinor,
                currencyCode: currency,
                paymentMethod: HomeOrdersText.trimmed(paymentMethod),
                sourceURL: trimmedSourceURL,
                estimateText: trimmedEstimate,
                fulfillmentStatus: .ordered,
                resolutionStatus: .none,
                estimateStart: estimateRange.start,
                estimateEnd: estimateRange.end,
                estimatePrecision: estimatePrecision,
                nextCheckAt: nextCheckEnabled ? nextCheckAt : nil,
                trackingNumber: HomeOrdersText.trimmed(trackingNumber),
                carrier: HomeOrdersText.trimmed(carrier)
            )

            var items: [OrderItem] = []
            for draft in itemDrafts {
                guard let quantity = Int(HomeOrdersText.trimmed(draft.quantityText)) else { continue }
                let itemAmount = try AddOrderMoney.minorUnits(
                    from: draft.amountText,
                    fieldName: L("Item amount")
                )
                items.append(OrderItem(
                    name: HomeOrdersText.trimmed(draft.name),
                    variant: HomeOrdersText.trimmed(draft.variant),
                    quantity: quantity,
                    amountMinor: itemAmount,
                    order: order
                ))
            }
            order.items = items

            let purchase = Milestone(
                kind: .purchase,
                occurredAt: orderDate,
                title: L("Order placed"),
                note: trimmedEstimate.isEmpty
                    ? L("Original purchase details recorded in Keyvow.")
                    : trimmedEstimate,
                sourceURL: trimmedSourceURL.isEmpty ? nil : trimmedSourceURL,
                order: order
            )
            order.milestones = [purchase]

            var reminders: [HeldReminder] = []
            if nextCheckEnabled {
                reminders.append(HeldReminder(
                    kind: .checkIn,
                    triggerAt: nextCheckAt,
                    leadDays: 0,
                    enabled: true,
                    label: L("Check in with %@", trimmedVendor),
                    order: order
                ))
            }
            if deadlineReminderEnabled {
                reminders.append(HeldReminder(
                    kind: .deadline,
                    triggerAt: deadlineReminderAt,
                    leadDays: deadlineLeadDays,
                    enabled: true,
                    label: L("Review the deadline for %@", trimmedTitle),
                    order: order
                ))
            }
            order.reminders = reminders

            let appSettings = try AppSettings.fetchOrCreate(context: modelContext)
            let persistedOrders = try modelContext.fetch(FetchDescriptor<HeldOrder>())
            let activeCount = persistedOrders.filter(\.isActive).count
            guard purchaseService.isPro || appSettings.proUnlocked || activeCount < 3 else {
                validationMessage = L("Free includes up to 3 active orders. Upgrade for unlimited active orders, or resolve an existing order before saving.")
                showingProUpgrade = true
                return
            }

            // Minimal receipt addition: keep the existing validation and save flow intact.
            try attachReviewedReceiptImages(to: order, importedPaths: &importedReceiptPaths)
            modelContext.insert(order)
            try modelContext.save()
            didPersistOrder = true

            if let pendingShare {
                PendingShareStore.shared.consumeAfterImport(id: pendingShare.id)
            }
            if appSettings.remindersEnabled && !reminders.isEmpty,
               reminderScheduler.authorizationStatus == .notDetermined {
                _ = await reminderScheduler.requestAuthorization()
            }
            await reminderScheduler.sync(orders: persistedOrders + [order], settings: appSettings)
            dismiss()
        } catch {
            modelContext.rollback()
            if !didPersistOrder, let store = try? AttachmentStore() {
                for path in importedReceiptPaths {
                    try? store.remove(relativePath: path)
                }
            }
            if let inputError = error as? AddOrderInputError {
                validationMessage = inputError.message
            } else {
                validationMessage = L("The order could not be saved. Please check the details and try again.")
            }
        }
    }

    // MARK: Shared-share prefill and OCR intake

    private func attachReviewedReceiptImages(
        to order: HeldOrder,
        importedPaths: inout [String]
    ) throws {
        guard !reviewedReceiptImages.isEmpty else { return }
        do {
            let store = try AttachmentStore()
            for image in reviewedReceiptImages {
                let metadata = try store.importData(
                    image.data,
                    originalFilename: image.filename,
                    mimeType: image.mimeType
                )
                importedPaths.append(metadata.relativePath)
                order.evidence.append(Evidence(
                    kind: .receipt,
                    title: L("Reviewed OCR receipt"),
                    filename: metadata.filename,
                    capturedAt: Date(),
                    source: L("New order OCR review"),
                    note: L("Original image retained only after user-confirmed OCR review."),
                    localRelativePath: metadata.relativePath,
                    mimeType: metadata.mimeType,
                    fileSize: metadata.fileSize,
                    sha256: metadata.sha256,
                    order: order
                ))
            }
        } catch {
            throw AddOrderInputError(
                L("The order was not saved because the reviewed OCR image could not be stored. %@", error.localizedDescription)
            )
        }
    }

    private func applyPendingShareIfNeeded() {
        guard !didApplyPendingShare, let pendingShare else { return }
        didApplyPendingShare = true
        title = pendingShare.suggestedTitle
        sourceURL = pendingShare.sourceURL
        // Vendor is deliberately not inferred from a URL or shared text.
        ocrStatusMessage = L("Shared details are pre-filled only. Add the vendor and review everything before saving.")
    }

    private func cancelNewOrder() {
        if let pendingShare {
            PendingShareStore.shared.discardAfterCancellation(id: pendingShare.id)
        }
        dismiss()
    }

    private func cancelOCRReview() {
        ocrResult = nil
        ocrReviewImages = []
        ocrStatusMessage = L("OCR review cancelled. No suggestions or receipt image were added.")
    }

    private func recognizePhoto(_ item: PhotosPickerItem) async {
        isRecognizing = true
        ocrStatusMessage = nil
        defer {
            isRecognizing = false
            selectedPhoto = nil
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self), !data.isEmpty else {
                ocrStatusMessage = L("No readable image was selected. Continue with the manual form below.")
                return
            }
            let result = try await OCREngine().recognizeText(data: data)
            ocrReviewImages = [OCRReviewedImage(data: data, pageNumber: 1)]
            ocrResult = result
        } catch {
            ocrReviewImages = []
            ocrStatusMessage = L("Text recognition could not read this image. %@ You can continue manually.", error.localizedDescription)
        }
    }

    private func recognizeScannedImages(_ images: [UIImage]) async {
        isRecognizing = true
        ocrStatusMessage = nil
        defer { isRecognizing = false }

        let dataItems = images.compactMap { $0.jpegData(compressionQuality: 0.92) }
        guard dataItems.count == images.count, !dataItems.isEmpty else {
            ocrReviewImages = []
            ocrStatusMessage = L("The scanned pages could not be prepared for OCR. Choose a photo or continue manually.")
            return
        }

        do {
            let result = try await OCREngine().recognizeText(dataItems: dataItems)
            ocrReviewImages = dataItems.enumerated().map {
                OCRReviewedImage(data: $0.element, pageNumber: $0.offset + 1)
            }
            ocrResult = result
        } catch {
            ocrReviewImages = []
            ocrStatusMessage = L("Text recognition could not read this scan. %@ You can continue manually.", error.localizedDescription)
        }
    }

    private func applyOCRSuggestions(_ suggestions: OCRConfirmedSuggestions) {
        if let suggestedTitle = suggestions.productTitle {
            title = suggestedTitle
        }
        if let suggestedVendor = suggestions.vendor {
            vendor = suggestedVendor
        }
        if let suggestedDeliveryText = suggestions.estimatedDeliveryText {
            estimateText = suggestedDeliveryText
        }
        if let suggestedOrderNumber = suggestions.orderNumber {
            orderNumber = suggestedOrderNumber
        }
        if let suggestedOrderDate = suggestions.orderDate {
            orderDate = suggestedOrderDate
        }
        if let suggestedAmount = suggestions.amount {
            amountText = NSDecimalNumber(decimal: suggestedAmount).stringValue
        }
        if let suggestedCurrency = suggestions.currency {
            currency = suggestedCurrency
        }
        reviewedReceiptImages = ocrReviewImages
        ocrReviewImages = []
        ocrResult = nil
        ocrStatusMessage = L("OCR review complete. Review the fields before saving; the original image will be stored as receipt evidence.")
        validationMessage = nil
    }
}

private enum AddOrderMoney {
    private static let posixLocale = Locale(identifier: "en_US_POSIX")
    private static let amountPattern = #"^\+?(?:(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d{1,2})?|\.\d{1,2})$"#

    static func minorUnits(from text: String, fieldName: String) throws -> Int64? {
        let trimmed = HomeOrdersText.trimmed(text)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.range(of: amountPattern, options: .regularExpression) != nil else {
            throw AddOrderInputError(L("%@ must be a non-negative amount with no more than two decimal places.", fieldName))
        }

        let normalized = trimmed
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "+", with: "")
        guard let decimal = Decimal(string: normalized, locale: posixLocale),
              !decimal.isNaN,
              decimal >= 0 else {
            throw AddOrderInputError(L("%@ could not be read as an amount.", fieldName))
        }

        var unrounded = decimal * Decimal(100)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &unrounded, 0, .plain)
        guard !rounded.isNaN, rounded <= Decimal(Int64.max) else {
            throw AddOrderInputError(L("%@ is too large to store safely.", fieldName))
        }

        let minorString = NSDecimalNumber(decimal: rounded).stringValue
        guard let minor = Int64(minorString) else {
            throw AddOrderInputError(L("%@ is too large to store safely.", fieldName))
        }
        return minor
    }
}
