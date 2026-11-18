import SwiftUI
import SwiftData
import UIKit
import UniformTypeIdentifiers
import UserNotifications

public struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var reminderScheduler: ReminderScheduler
    @EnvironmentObject private var purchaseService: PurchaseService
    @EnvironmentObject private var localization: LocalizationCenter

    @Query(sort: \HeldOrder.orderedAt, order: .reverse) private var orders: [HeldOrder]
    @Query private var storedSettings: [AppSettings]

    @State private var attachmentStore: AttachmentStore?
    @State private var storageDescription = L("Calculating…")
    @State private var storageErrorMessage: String?
    @State private var settingsErrorMessage: String?
    @State private var notificationMessage: String?

    @State private var showingExportPreview = false
    @State private var showingImporter = false
    @State private var isPreviewingImport = false
    @State private var isRestoring = false
    @State private var pendingRestore: PendingRestore?
    @State private var temporaryImportURL: URL?
    @State private var importErrorMessage: String?
    @State private var restoreSuccessMessage: String?

    private let exportService = ExportService()

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                introduction

                if let settings = currentSettings {
                    appearanceSection(settings)
                    languageSection(settings)
                    notificationsSection(settings)
                    preferencesSection(settings)
                    proSection(settings)
                    storageSection
                    backupSection(settings)
                    privacySection
                } else {
                    Section {
                        HStack(spacing: HeldSpacing.small) {
                            ProgressView()
                            Text(L("Preparing local settings…"))
                                .foregroundStyle(HeldColor.secondaryInk)
                        }
                    }
                }

                if let settingsErrorMessage {
                    Section {
                        Label(settingsErrorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(HeldColor.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .heldScreenBackground()
            .heldNavigationTitle(L("Settings"))
            .task {
                await initialLoad()
            }
            .onChange(of: localization.language) { _, _ in
                refreshStorage()
            }
            .onChange(of: scenePhase) { phase in
                guard phase == .active else { return }
                refreshStorage()
                Task { @MainActor in
                    await reminderScheduler.refreshAuthorizationStatus()
                }
            }
            .sheet(isPresented: $showingExportPreview) {
                if let settings = currentSettings {
                    ExportPrivacyView(
                        orders: orders,
                        settings: settings,
                        attachmentStore: attachmentStore
                    )
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.json, .zip],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    previewImport(at: url)
                case .failure(let error):
                    importErrorMessage = error.localizedDescription
                }
            }
            .sheet(item: $pendingRestore, onDismiss: finishRestoreSheet) { pending in
                RestoreConfirmationView(
                    pending: pending,
                    currentOrderCount: orders.count,
                    isRestoring: isRestoring,
                    errorMessage: importErrorMessage,
                    onConfirm: { mode in
                        restore(pending, mode: mode)
                    }
                )
            }
            .heldLoadingOverlay(isPresented: isPreviewingImport, title: L("Reading backup…"))
        }
    }

    private var currentSettings: AppSettings? {
        storedSettings.first { $0.id == "main" } ?? storedSettings.first
    }

    private var introduction: some View {
        Section {
            VStack(alignment: .leading, spacing: HeldSpacing.small) {
                Text(L("Keyvow, on your terms."))
                    .heldDisplay(size: 28)
                    .foregroundStyle(HeldColor.ink)
                Text(L("Your records remain yours: quiet preferences, portable backups, and full access to every order you have saved."))
                    .heldBody()
                    .foregroundStyle(HeldColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, HeldSpacing.small)
            .accessibilityElement(children: .combine)
        }
        .listRowBackground(Color.clear)
    }

    private func appearanceSection(_ settings: AppSettings) -> some View {
        Section {
            Picker(L("Appearance"), selection: Binding(
                get: { settings.preferredColorSchemeRaw },
                set: { value in
                    settings.preferredColorSchemeRaw = value
                    saveSettings()
                }
            )) {
                Text(L("System")).tag("system")
                Text(L("Light")).tag("light")
                Text(L("Dark")).tag("dark")
            }
        } header: {
            Label(L("Appearance"), systemImage: "circle.lefthalf.filled")
        } footer: {
            Text(L("System follows your iPhone appearance. Light and dark apply Keyvow’s ivory, forest, and amber palette accordingly."))
        }
    }

    private func languageSection(_ settings: AppSettings) -> some View {
        Section {
            Picker(L("Language"), selection: Binding(
                get: { localization.language },
                set: { updateLanguage($0, settings: settings) }
            )) {
                ForEach(AppLanguage.allCases, id: \.self) { language in
                    Text(language.nativeDisplayName).tag(language)
                }
            }
        } header: {
            Label(L("Language"), systemImage: "globe")
        } footer: {
            Text(L("Language changes apply immediately. Your order content stays unchanged, and pending reminders keep their dates and lead times."))
        }
    }

    private func updateLanguage(_ language: AppLanguage, settings: AppSettings) {
        LocalizationCenter.shared.setLanguage(language)
        settings.preferredLanguageRaw = language.rawValue
        saveSettings()
        Task { @MainActor in
            await reminderScheduler.sync(orders: orders, settings: settings)
        }
    }

    private func notificationsSection(_ settings: AppSettings) -> some View {
        Section {
            Toggle(L("Order reminders"), isOn: Binding(
                get: { settings.remindersEnabled },
                set: { enabled in
                    updateReminders(enabled, settings: settings)
                }
            ))

            Label(
                L(reminderScheduler.authorizationStatusDescription),
                systemImage: notificationStatusSymbol
            )
            .heldCaption()
            .foregroundStyle(HeldColor.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)

            if reminderScheduler.authorizationStatus == .denied {
                Button(L("Open Notification Settings")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .heldButtonStyle(.secondary)
            }

            if let notificationMessage {
                Text(L(notificationMessage))
                    .heldCaption()
                    .foregroundStyle(HeldColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let schedulerError = reminderScheduler.lastErrorMessage,
               schedulerError != notificationMessage {
                Label(L(schedulerError), systemImage: "exclamationmark.triangle")
                    .heldCaption()
                    .foregroundStyle(HeldColor.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Label(L("Notifications"), systemImage: "bell")
        } footer: {
            Text(L("The authorization prompt appears only when you turn reminders on. Turning reminders off removes Keyvow’s pending order notifications; it does not change iOS permission."))
        }
    }

    private var notificationStatusSymbol: String {
        switch reminderScheduler.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "checkmark.circle"
        case .denied:
            return "bell.slash"
        case .notDetermined:
            return "bell.badge"
        @unknown default:
            return "questionmark.circle"
        }
    }

    private func preferencesSection(_ settings: AppSettings) -> some View {
        Section {
            Stepper(value: Binding(
                get: { settings.staleDays },
                set: { value in
                    settings.staleDays = min(3_650, max(0, value))
                    saveSettings()
                }
            ), in: 0...3_650) {
                VStack(alignment: .leading) {
                    Text(L("Stale order threshold"))
                    Text(L("%1$lld days without an update", Int64(settings.staleDays)))
                        .heldCaption()
                        .foregroundStyle(HeldColor.secondaryInk)
                }
            }

            Stepper(value: Binding(
                get: { settings.leadDays },
                set: { value in
                    settings.leadDays = min(365, max(0, value))
                    saveSettings()
                }
            ), in: 0...365) {
                VStack(alignment: .leading) {
                    Text(L("Default reminder lead time"))
                    Text(L("%1$lld days", Int64(settings.leadDays)))
                        .heldCaption()
                        .foregroundStyle(HeldColor.secondaryInk)
                }
            }

            Toggle(L("Monday morning digest"), isOn: Binding(
                get: { settings.weeklyDigest },
                set: { value in
                    settings.weeklyDigest = value
                    saveSettings()
                    Task { @MainActor in
                        await reminderScheduler.sync(orders: orders, settings: settings)
                    }
                }
            ))
        } header: {
            Label(L("Order preferences"), systemImage: "slider.horizontal.3")
        } footer: {
            Text(L("The stale threshold affects attention cues. Default lead time is for newly created reminders; existing reminders keep their own dates. With order reminders enabled, the digest arrives each Monday at 9:00 AM with active-order and attention counts. It uses local notifications, not a server."))
        }
    }

    private func proSection(_ settings: AppSettings) -> some View {
        Section {
            HeldCard(padding: HeldSpacing.medium) {
                VStack(alignment: .leading, spacing: HeldSpacing.medium) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: HeldSpacing.extraSmall) {
                            Text(L("Keyvow Pro"))
                                .heldTitle()
                                .foregroundStyle(HeldColor.ink)
                            Text(L("One lifetime upgrade. Unlimited active orders."))
                                .font(.subheadline)
                                .foregroundStyle(HeldColor.secondaryInk)
                        }
                        Spacer()
                        if purchaseService.isPro || settings.proUnlocked {
                            HeldBadge(text: L("Unlocked"), tone: .success)
                        }
                    }

                    Text(L("The free version includes up to 3 active orders. Keyvow Pro is an optional, one-time lifetime upgrade with unlimited active orders. Your existing orders, evidence, backups, CSV exports, PDF reports, and restore remain available in both versions."))
                        .heldBody()
                        .foregroundStyle(HeldColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)

                    if purchaseService.isLoading {
                        HStack(spacing: HeldSpacing.small) {
                            ProgressView()
                            Text(L("Contacting the App Store…"))
                                .heldCaption()
                                .foregroundStyle(HeldColor.secondaryInk)
                        }
                    }

                    if !(purchaseService.isPro || settings.proUnlocked) {
                        if let price = purchaseService.displayPrice {
                            Button(L("Get Keyvow Pro — %@", price)) {
                                purchase(settings)
                            }
                            .heldButtonStyle(.primary)
                            .disabled(purchaseService.isLoading)
                        } else {
                            Button(L("Load Keyvow Pro")) {
                                Task { @MainActor in
                                    await purchaseService.loadProduct()
                                }
                            }
                            .heldButtonStyle(.secondary)
                            .disabled(purchaseService.isLoading)
                        }
                    }

                    Button(L("Restore Purchases")) {
                        restorePurchases(settings)
                    }
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
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)
        } header: {
            Text(L("Optional upgrade"))
        } footer: {
            Text(L("Purchases and restores are verified by StoreKit. Restoring a backup never unlocks Pro."))
        }
    }

    private var storageSection: some View {
        Section {
            LabeledContent(L("Evidence files"), value: storageDescription)

            if let storageErrorMessage {
                Label(storageErrorMessage, systemImage: "exclamationmark.triangle")
                    .heldCaption()
                    .foregroundStyle(HeldColor.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Label(L("Local storage"), systemImage: "internaldrive")
        } footer: {
            Text(L("This is the size of original files in Keyvow’s local evidence folder. SwiftData records and temporary exports are not included."))
        }
    }

    private func backupSection(_ settings: AppSettings) -> some View {
        Section {
            Button {
                showingExportPreview = true
            } label: {
                Label(L("Export or Share Data"), systemImage: "square.and.arrow.up")
                    .foregroundStyle(HeldColor.accent)
            }

            Button {
                importErrorMessage = nil
                restoreSuccessMessage = nil
                showingImporter = true
            } label: {
                Label(L("Restore from JSON or ZIP"), systemImage: "square.and.arrow.down")
                    .foregroundStyle(HeldColor.accent)
            }

            if let importErrorMessage, pendingRestore == nil {
                Label(importErrorMessage, systemImage: "exclamationmark.triangle")
                    .heldCaption()
                    .foregroundStyle(HeldColor.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let restoreSuccessMessage {
                Label(restoreSuccessMessage, systemImage: "checkmark.circle")
                    .heldCaption()
                    .foregroundStyle(HeldColor.success)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Label(L("Backup and restore"), systemImage: "archivebox")
        } footer: {
            Text(L("Export a restorable JSON manifest, a ZIP with original evidence, a CSV spreadsheet, or a PDF evidence report. Every restore shows a preview first. Merge updates matching orders; Replace requires a separate destructive confirmation."))
        }
    }

    private var privacySection: some View {
        Section {
            Text(L("Orders, evidence, and preferences are stored locally on this iPhone. Keyvow has no account system, analytics, advertising trackers, or developer backend. Nothing is shared unless you choose an export; App Store purchases are handled by Apple."))
                .heldBody()
                .foregroundStyle(HeldColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            Text(L("Evidence files live in Keyvow’s Application Support evidence folder with iOS file protection. Exports are created in temporary storage and leave the app only through your share-sheet action."))
                .heldBody()
                .foregroundStyle(HeldColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            LabeledContent(L("Version"), value: "1.0")
        } header: {
            Label(L("Privacy and about"), systemImage: "hand.raised")
        }
    }

    @MainActor
    private func initialLoad() async {
        do {
            let settings = try AppSettings.fetchOrCreate(context: modelContext)
            try modelContext.save()
            settingsErrorMessage = nil
            refreshStorage()
            await reminderScheduler.refreshAuthorizationStatus()
            await purchaseService.synchronize(settings: settings)
            try modelContext.save()
            if purchaseService.product == nil && !purchaseService.isLoading {
                await purchaseService.loadProduct()
            }
        } catch {
            settingsErrorMessage = error.localizedDescription
        }
    }

    private func saveSettings() {
        do {
            try modelContext.save()
            settingsErrorMessage = nil
        } catch {
            settingsErrorMessage = L("Settings could not be saved: %@", error.localizedDescription)
        }
    }

    private func updateReminders(_ enabled: Bool, settings: AppSettings) {
        notificationMessage = nil
        Task { @MainActor in
            if !enabled {
                settings.remindersEnabled = false
                saveSettings()
                await reminderScheduler.sync(orders: orders, settings: settings)
                notificationMessage = L("Order reminders are off. Keyvow’s pending order notifications have been removed.")
                return
            }

            if reminderScheduler.authorizationStatus == .denied {
                settings.remindersEnabled = false
                saveSettings()
                notificationMessage = L("Notifications are denied in iOS. Open Notification Settings to allow them, then return and turn reminders on.")
                return
            }

            switch reminderScheduler.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                break
            case .notDetermined:
                let granted = await reminderScheduler.requestAuthorization()
                guard granted else {
                    settings.remindersEnabled = false
                    saveSettings()
                    notificationMessage = reminderScheduler.lastErrorMessage
                    return
                }
            case .denied:
                return
            @unknown default:
                let granted = await reminderScheduler.requestAuthorization()
                guard granted else {
                    settings.remindersEnabled = false
                    saveSettings()
                    notificationMessage = reminderScheduler.lastErrorMessage ?? L("Notifications are unavailable.")
                    return
                }
            }

            settings.remindersEnabled = true
            saveSettings()
            await reminderScheduler.sync(orders: orders, settings: settings)
            notificationMessage = reminderScheduler.lastErrorMessage == nil
                ? L("Order reminders are on and synchronized with your saved reminder dates.")
                : L("Order reminders are on, but some notifications could not be scheduled.")
        }
    }

    private func purchase(_ settings: AppSettings) {
        Task { @MainActor in
            await purchaseService.purchase(settings: settings)
            saveSettings()
        }
    }

    private func restorePurchases(_ settings: AppSettings) {
        Task { @MainActor in
            await purchaseService.restorePurchases(settings: settings)
            saveSettings()
        }
    }

    private func refreshStorage() {
        do {
            let store = try ensureAttachmentStore()
            let bytes = try store.totalBytes()
            storageDescription = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            storageErrorMessage = nil
        } catch {
            storageDescription = L("Unavailable")
            storageErrorMessage = L("Evidence storage could not be measured: %@", error.localizedDescription)
        }
    }

    @discardableResult
    private func ensureAttachmentStore() throws -> AttachmentStore {
        if let attachmentStore { return attachmentStore }
        let store = try AttachmentStore()
        attachmentStore = store
        return store
    }

    private func previewImport(at sourceURL: URL) {
        guard !isPreviewingImport && !isRestoring else { return }
        isPreviewingImport = true
        importErrorMessage = nil
        restoreSuccessMessage = nil

        Task { @MainActor in
            await Task.yield()
            defer { isPreviewingImport = false }

            do {
                cleanupImportFile()
                let pathExtension = sourceURL.pathExtension.lowercased()
                guard pathExtension == "json" || pathExtension == "zip" else {
                    throw ExportServiceError.invalidBackup(L("Choose a Keyvow JSON or ZIP backup."))
                }

                let didStartAccess = sourceURL.startAccessingSecurityScopedResource()
                defer {
                    if didStartAccess {
                        sourceURL.stopAccessingSecurityScopedResource()
                    }
                }

                let temporaryURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("Held-Restore-\(UUID().uuidString)")
                    .appendingPathExtension(pathExtension)
                try FileManager.default.copyItem(at: sourceURL, to: temporaryURL)
                temporaryImportURL = temporaryURL

                let preview: RestorePreview
                let isArchive = pathExtension == "zip"
                if isArchive {
                    preview = try exportService.previewArchive(at: temporaryURL)
                } else {
                    let data = try Data(contentsOf: temporaryURL, options: .mappedIfSafe)
                    preview = try exportService.previewJSON(data)
                }
                pendingRestore = PendingRestore(
                    preview: preview,
                    fileURL: temporaryURL,
                    isArchive: isArchive
                )
            } catch {
                cleanupImportFile()
                importErrorMessage = error.localizedDescription
            }
        }
    }

    private func restore(_ pending: PendingRestore, mode: RestoreMode) {
        guard !isRestoring else { return }
        isRestoring = true
        importErrorMessage = nil

        Task { @MainActor in
            await Task.yield()
            defer { isRestoring = false }

            do {
                let store = try ensureAttachmentStore()
                let result = try exportService.restore(
                    pending.preview,
                    mode: mode,
                    context: modelContext,
                    attachmentStore: store,
                    archiveURL: pending.isArchive ? pending.fileURL : nil
                )

                // Re-fetch the restored graph and settings before synchronizing.
                // Sync never requests notification authorization by itself.
                let restoredOrders = try modelContext.fetch(FetchDescriptor<HeldOrder>())
                let restoredSettings = try AppSettings.fetchOrCreate(context: modelContext)
                LocalizationCenter.shared.setLanguage(AppLanguage(rawValueOrSystem: restoredSettings.preferredLanguageRaw))
                await reminderScheduler.sync(orders: restoredOrders, settings: restoredSettings)

                let summary = result.restoredEvidenceCount == 1
                    ? L("Restore complete: %1$lld inserted, %2$lld updated, and %3$lld evidence file restored. Reminders were synchronized.", Int64(result.insertedOrderCount), Int64(result.updatedOrderCount), Int64(result.restoredEvidenceCount))
                    : L("Restore complete: %1$lld inserted, %2$lld updated, and %3$lld evidence files restored. Reminders were synchronized.", Int64(result.insertedOrderCount), Int64(result.updatedOrderCount), Int64(result.restoredEvidenceCount))
                if let schedulerError = reminderScheduler.lastErrorMessage {
                    restoreSuccessMessage = L("%1$@ %2$@", summary, L(schedulerError))
                } else {
                    restoreSuccessMessage = summary
                }
                refreshStorage()
                pendingRestore = nil
            } catch {
                importErrorMessage = error.localizedDescription
            }
        }
    }

    private func finishRestoreSheet() {
        cleanupImportFile()
        isRestoring = false
    }

    private func cleanupImportFile() {
        guard let temporaryImportURL else { return }
        try? FileManager.default.removeItem(at: temporaryImportURL)
        self.temporaryImportURL = nil
    }
}
