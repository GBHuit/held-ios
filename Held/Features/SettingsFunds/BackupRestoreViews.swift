import SwiftUI
import SwiftData
import UIKit

// MARK: - Export privacy preview

struct ExportPrivacyView: View {
    @EnvironmentObject private var localization: LocalizationCenter
    let orders: [HeldOrder]
    let settings: AppSettings
    let attachmentStore: AttachmentStore?

    @Environment(\.dismiss) private var dismiss
    @State private var exportKind: HeldExportKind = .archive
    @State private var confirmedChecks: Set<String> = []
    @State private var shareDocument: ShareDocument?
    @State private var isPreparing = false
    @State private var errorMessage: String?

    private let exportService = ExportService()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(L("Export type"), selection: $exportKind) {
                        ForEach(HeldExportKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .onChange(of: exportKind) { _ in
                        confirmedChecks.removeAll()
                        errorMessage = nil
                    }

                    Text(exportKind.summary)
                        .heldBody()
                        .foregroundStyle(HeldColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text(L("Choose a portable format"))
                }

                Section {
                    ForEach(exportKind.privacyChecks, id: \.self) { check in
                        Toggle(isOn: confirmationBinding(for: check)) {
                            Text(L(check))
                                .heldBody()
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .toggleStyle(HeldCheckboxToggleStyle())
                    }

                    Text(L("These checks confirm that you reviewed the contents; they do not filter fields. Choose another export type to change what leaves this device."))
                        .heldCaption()
                        .foregroundStyle(HeldColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text(L("Privacy review"))
                } footer: {
                    Text(L("The file is created in temporary app storage. You decide where it goes in the share sheet."))
                }

                if let errorMessage {
                    Section {
                        Label(L(errorMessage), systemImage: "exclamationmark.triangle")
                            .foregroundStyle(HeldColor.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if exportKind == .archive && attachmentStore == nil {
                    Section {
                        Label(L("Evidence storage is unavailable. Choose JSON, CSV, or PDF, or return to Settings and try again."), systemImage: "externaldrive.badge.exclamationmark")
                            .foregroundStyle(HeldColor.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Section {
                    Button {
                        Task { @MainActor in
                            await prepareAndShare()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Label(L("Export and Share"), systemImage: "square.and.arrow.up")
                            Spacer()
                        }
                    }
                    .heldButtonStyle(.primary)
                    .disabled(!canExport || isPreparing)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }
            }
            .scrollContentBackground(.hidden)
            .heldScreenBackground()
            .navigationTitle(L("Privacy preview"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) { dismiss() }
                        .disabled(isPreparing)
                }
            }
            .heldLoadingOverlay(isPresented: isPreparing, title: L("Preparing your export…"))
            .interactiveDismissDisabled(isPreparing)
            .sheet(item: $shareDocument) { document in
                SettingsFundsActivityShareSheet(activityItems: [document.url])
            }
        }
    }

    private var canExport: Bool {
        guard exportKind != .archive || attachmentStore != nil else { return false }
        return Set(exportKind.privacyChecks).isSubset(of: confirmedChecks)
    }

    private func confirmationBinding(for check: String) -> Binding<Bool> {
        Binding(
            get: { confirmedChecks.contains(check) },
            set: { confirmed in
                if confirmed {
                    confirmedChecks.insert(check)
                } else {
                    confirmedChecks.remove(check)
                }
            }
        )
    }

    @MainActor
    private func prepareAndShare() async {
        guard canExport else { return }
        isPreparing = true
        errorMessage = nil
        await Task.yield()
        defer { isPreparing = false }

        do {
            let url: URL
            switch exportKind {
            case .json:
                url = try exportService.writeJSON(orders: orders, settings: settings)
            case .csv:
                url = try exportService.writeCSV(orders: orders)
            case .archive:
                guard let attachmentStore else {
                    throw ExportServiceError.archiveRequiresAttachmentStore
                }
                url = try exportService.writeArchive(
                    orders: orders,
                    settings: settings,
                    attachmentStore: attachmentStore
                )
            case .evidenceReport:
                url = try exportService.writeEvidenceReport(orders: orders)
            }
            shareDocument = ShareDocument(url: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum HeldExportKind: String, CaseIterable, Identifiable {
    case json
    case csv
    case archive
    case evidenceReport

    var id: String { rawValue }

    var title: String {
        switch self {
        case .json: return L("JSON backup")
        case .csv: return L("CSV orders")
        case .archive: return L("ZIP evidence backup")
        case .evidenceReport: return L("PDF evidence report")
        }
    }

    var summary: String {
        switch self {
        case .json:
            return L("A complete restorable manifest of orders, reminders, evidence metadata, and app preferences. Original evidence files are not embedded.")
        case .csv:
            return L("A spreadsheet of orders and item delivery status. CSV cannot be restored back into Keyvow.")
        case .archive:
            return L("A complete restorable backup with the JSON manifest and every referenced original evidence file.")
        case .evidenceReport:
            return L("A readable PDF of order and evidence metadata, notes, paths, sizes, and checksums. Original attachments are not embedded.")
        }
    }

    var privacyChecks: [String] {
        switch self {
        case .json:
            return [
                "I reviewed that order details, notes, items, milestones, and reminders are included.",
                "I reviewed that evidence metadata, filenames, local paths, and checksums are included.",
                "I reviewed that app preferences are included; a backup never restores Pro access."
            ]
        case .csv:
            return [
                "I reviewed that order details, notes, and item delivery status are included.",
                "I reviewed that CSV excludes evidence records, app preferences, and original attachments."
            ]
        case .archive:
            return [
                "I reviewed that order details, notes, reminders, and app preferences are included.",
                "I reviewed that evidence metadata and original attached evidence files are included.",
                "I reviewed that a backup never restores Pro access; StoreKit remains authoritative."
            ]
        case .evidenceReport:
            return [
                "I reviewed that order details and evidence titles, notes, and filenames are included.",
                "I reviewed that local paths, file sizes, and SHA-256 checksums are printed in the report."
            ]
        }
    }
}

private struct ShareDocument: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct HeldCheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.$isOn.wrappedValue.toggle()
        } label: {
            HStack(alignment: .top, spacing: HeldSpacing.small) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(configuration.isOn ? HeldColor.accent : HeldColor.secondaryInk)
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)
                configuration.label
                    .foregroundStyle(HeldColor.ink)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? L("Checked") : L("Not checked"))
    }
}

// MARK: - Restore preview and confirmation

struct PendingRestore: Identifiable {
    let id = UUID()
    let preview: RestorePreview
    let fileURL: URL
    let isArchive: Bool
}

struct RestoreConfirmationView: View {
    @EnvironmentObject private var localization: LocalizationCenter
    let pending: PendingRestore
    let currentOrderCount: Int
    let isRestoring: Bool
    let errorMessage: String?
    let onConfirm: (RestoreMode) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var choice: RestoreModeChoice = .merge
    @State private var showReplaceConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(L("Orders"), value: "\(pending.preview.orderCount)")
                    LabeledContent(L("Evidence records"), value: "\(pending.preview.evidenceCount)")
                    LabeledContent(
                        L("Recorded attachment size"),
                        value: ByteCountFormatter.string(
                            fromByteCount: pending.preview.attachmentBytes,
                            countStyle: .file
                        )
                    )
                    LabeledContent(
                        L("Exported"),
                        value: pending.preview.exportedAt.formatted(Date.FormatStyle(date: .long, time: .shortened, locale: localization.locale))
                    )
                } header: {
                    Text(L("Backup contents"))
                } footer: {
                    Text(pending.isArchive
                         ? L("This ZIP contains original evidence files. Every referenced file is verified before model changes are saved.")
                         : L("This JSON contains records only. Evidence metadata is restored, but unavailable local file references are cleared."))
                }

                Section {
                    Picker(L("Restore mode"), selection: $choice) {
                        ForEach(RestoreModeChoice.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityHint(L("Merge updates matching orders. Replace deletes existing orders after a second confirmation."))

                    Text(choice.explanation(currentOrderCount: currentOrderCount))
                        .heldBody()
                        .foregroundStyle(choice == .replace ? HeldColor.danger : HeldColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text(L("Choose explicitly"))
                }

                Section {
                    ForEach(pending.preview.warnings, id: \.self) { warning in
                        Label(L(warning), systemImage: "exclamationmark.triangle")
                            .heldCaption()
                            .foregroundStyle(HeldColor.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text(L("Before restoring"))
                }

                if let errorMessage {
                    Section {
                        Label(L(errorMessage), systemImage: "exclamationmark.octagon")
                            .foregroundStyle(HeldColor.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Section {
                    Button {
                        if choice == .replace {
                            showReplaceConfirmation = true
                        } else {
                            onConfirm(.merge)
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Text(choice == .merge ? L("Merge Backup") : L("Review Replace…"))
                            Spacer()
                        }
                    }
                    .heldButtonStyle(choice == .replace ? .secondary : .primary)
                    .tint(choice == .replace ? HeldColor.danger : HeldColor.accent)
                    .disabled(isRestoring)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }
            }
            .scrollContentBackground(.hidden)
            .heldScreenBackground()
            .navigationTitle(L("Restore preview"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) { dismiss() }
                        .disabled(isRestoring)
                }
            }
            .heldLoadingOverlay(isPresented: isRestoring, title: L("Restoring your backup…"))
            .interactiveDismissDisabled(isRestoring)
            .alert(
                L("Replace all existing orders?"),
                isPresented: $showReplaceConfirmation
            ) {
                Button(L("Replace Existing Orders"), role: .destructive) {
                    onConfirm(.replace)
                }
                Button(L("Cancel"), role: .cancel) {}
            } message: {
                Text(currentOrderCount == 1 ? L("This deletes the %lld order currently in Keyvow and replaces it with this backup. Unreferenced evidence files may also be removed after a successful restore. Keep another backup if you may need the current data later.", currentOrderCount) : L("This deletes the %lld orders currently in Keyvow and replaces them with this backup. Unreferenced evidence files may also be removed after a successful restore. Keep another backup if you may need the current data later.", currentOrderCount))
            }
        }
    }
}

private enum RestoreModeChoice: String, CaseIterable, Identifiable {
    case merge
    case replace

    var id: String { rawValue }
    var title: String {
        switch self {
        case .merge: return L("Merge")
        case .replace: return L("Replace")
        }
    }

    func explanation(currentOrderCount: Int) -> String {
        switch self {
        case .merge:
            return L("Adds new orders and updates orders with matching IDs. Your other existing orders remain in place.")
        case .replace:
            return currentOrderCount == 1 ? L("Deletes the %lld existing order after validation, then restores this backup. A destructive confirmation is required.", currentOrderCount) : L("Deletes all %lld existing orders after validation, then restores this backup. A destructive confirmation is required.", currentOrderCount)
        }
    }
}

// MARK: - Native share sheet

private struct SettingsFundsActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
