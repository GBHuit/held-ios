import SwiftUI
import UIKit
import QuickLook

// MARK: - Evidence draft and collection

struct EvidenceDraft: Identifiable {
    let id = UUID()
    var kind = EvidenceKind.receipt
    var title = ""
    var capturedAt = Date()
    var source = ""
    var note = ""
    var referenceFilename = "Evidence note.txt"
    var attachment: AttachmentMetadata?
    var confirmed = false
}

struct OrderEvidenceSection: View {
    @EnvironmentObject private var localization: LocalizationCenter
    let order: HeldOrder
    let attachmentStore: AttachmentStore?
    let storageError: String?
    let onSelect: (Evidence) -> Void
    let onAddDetails: () -> Void
    let onImportFile: () -> Void
    let onImportPhoto: () -> Void
    let onScanText: () -> Void

    private var evidence: [Evidence] {
        order.evidence.sorted {
            if $0.capturedAt == $1.capturedAt { return $0.id < $1.id }
            return $0.capturedAt > $1.capturedAt
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HeldSpacing.medium) {
            HeldSectionHeader(
                title: L("Evidence"),
                subtitle: L("Original metadata, notes, sources, capture dates, and checksums remain read-only after saving.")
            ) {
                Menu {
                    Button(action: onAddDetails) {
                        Label(L("Add evidence details"), systemImage: "square.and.pencil")
                    }
                    Button(action: onImportFile) {
                        Label(L("Import file"), systemImage: "folder")
                    }
                    Button(action: onImportPhoto) {
                        Label(L("Import photo"), systemImage: "photo.on.rectangle")
                    }
                    Button(action: onScanText) {
                        Label(L("Scan live text"), systemImage: "text.viewfinder")
                    }
                } label: {
                    Label(L("Add evidence"), systemImage: "plus")
                        .font(HeldFont.button)
                        .foregroundStyle(HeldColor.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(minHeight: 44)
                        .background(HeldColor.accentSoft.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .accessibilityLabel(L("Add evidence"))
            }

            if let storageError {
                OrderDetailCallout(
                    title: L("Attachment storage unavailable"),
                    message: storageError,
                    symbolName: "externaldrive.badge.exclamationmark",
                    tone: .danger
                )
            }

            if evidence.isEmpty {
                HeldCard {
                    Text(L("No evidence yet. Preserve a receipt, original listing, terms, communication, or shipping record."))
                        .foregroundStyle(HeldColor.secondaryInk)
                }
            } else {
                VStack(spacing: HeldSpacing.small) {
                    ForEach(evidence, id: \.id) { item in
                        Button {
                            onSelect(item)
                        } label: {
                            EvidenceRow(evidence: item, attachmentStore: attachmentStore)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(L("Opens immutable evidence details and preview actions"))
                    }
                }
            }
        }
    }
}

private struct EvidenceRow: View {
    @EnvironmentObject private var localization: LocalizationCenter
    let evidence: Evidence
    let attachmentStore: AttachmentStore?

    var body: some View {
        HeldCard(padding: HeldSpacing.medium) {
            HStack(alignment: .top, spacing: HeldSpacing.medium) {
                EvidenceThumbnail(evidence: evidence, attachmentStore: attachmentStore, pixelSize: 180)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: HeldSpacing.extraSmall) {
                    HStack(alignment: .top) {
                        Text(evidence.title)
                            .font(.headline)
                            .foregroundStyle(HeldColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: HeldSpacing.small)
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(HeldColor.secondaryInk)
                            .accessibilityLabel(L("Metadata locked"))
                    }
                    Text(localizedEvidenceKindLabel(evidence.kind))
                        .heldCaption()
                        .foregroundStyle(HeldColor.accent)
                    Text(evidence.filename)
                        .heldCaption()
                        .foregroundStyle(HeldColor.secondaryInk)
                        .lineLimit(2)
                    Text(L("Captured %@", localization.date(evidence.capturedAt)))
                        .heldCaption()
                        .foregroundStyle(HeldColor.secondaryInk)
                }
            }
        }
    }
}

struct EvidenceThumbnail: View {
    @EnvironmentObject private var localization: LocalizationCenter
    let evidence: Evidence
    let attachmentStore: AttachmentStore?
    let pixelSize: Int

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .accessibilityLabel(L("Thumbnail for %@", evidence.title))
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(HeldColor.accentSoft)
                Image(systemName: evidence.kind.symbolName)
                    .font(.title2)
                    .foregroundStyle(HeldColor.accent)
                    .accessibilityHidden(true)
            }
        }
        .clipped()
        .task(id: evidence.localRelativePath) {
            guard let attachmentStore, let path = evidence.localRelativePath else { return }
            image = try? attachmentStore.thumbnail(forRelativePath: path, maxPixelSize: pixelSize)
        }
    }
}

// MARK: - Confirmed evidence entry and OCR

@MainActor
struct EvidenceEntrySheet: View {
    @EnvironmentObject private var localization: LocalizationCenter
    let attachmentStore: AttachmentStore?
    let onSave: (EvidenceDraft) throws -> Void
    let onCancel: (EvidenceDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: EvidenceDraft
    @State private var errorMessage: String?
    @State private var ocrMessage: String?
    @State private var isRecognizingText = false

    init(
        draft: EvidenceDraft,
        attachmentStore: AttachmentStore?,
        onSave: @escaping (EvidenceDraft) throws -> Void,
        onCancel: @escaping (EvidenceDraft) -> Void
    ) {
        self.attachmentStore = attachmentStore
        self.onSave = onSave
        self.onCancel = onCancel
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let attachment = draft.attachment {
                    Section(L("Imported file · locked after save")) {
                        OrderDetailMetadataRow(title: L("Filename"), value: attachment.filename)
                        OrderDetailMetadataRow(title: L("MIME type"), value: attachment.mimeType)
                        OrderDetailMetadataRow(title: L("File size"), value: orderDetailFileSize(attachment.fileSize))
                        OrderDetailMetadataRow(title: L("SHA-256"), value: attachment.sha256, monospaced: true)
                    }
                } else {
                    Section(L("Evidence reference")) {
                        TextField(L("Reference filename"), text: $draft.referenceFilename)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Text(L("This creates an evidence metadata record without an attachment. Add an imported file or photo when the original file is available."))
                            .heldCaption()
                            .foregroundStyle(HeldColor.secondaryInk)
                    }
                }

                Section(L("Evidence details")) {
                    Picker(L("Kind"), selection: $draft.kind) {
                        ForEach(EvidenceKind.allCases, id: \.self) { kind in
                            Label(localizedEvidenceKindLabel(kind), systemImage: kind.symbolName).tag(kind)
                        }
                    }
                    TextField(L("Title"), text: $draft.title)
                    TextField(L("Source"), text: $draft.source, axis: .vertical)
                        .lineLimit(2...4)
                    DatePicker(
                        L("Captured at"),
                        selection: $draft.capturedAt,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                Section(L("Note · editable")) {
                    TextField(L("Evidence note or recognized text"), text: $draft.note, axis: .vertical)
                        .lineLimit(6...16)
                    if canRecognizeImageText {
                        Button {
                            recognizeImageText()
                        } label: {
                            if isRecognizingText {
                                Label(L("Recognizing text…"), systemImage: "text.viewfinder")
                            } else {
                                Label(L("Recognize text in image"), systemImage: "text.viewfinder")
                            }
                        }
                        .disabled(isRecognizingText)
                    }
                    if let ocrMessage {
                        Text(L(ocrMessage))
                            .heldCaption()
                            .foregroundStyle(HeldColor.secondaryInk)
                    }
                }

                Section {
                    Toggle(isOn: $draft.confirmed) {
                        VStack(alignment: .leading, spacing: HeldSpacing.extraSmall) {
                            Text(L("I reviewed these details"))
                            Text(L("Save this evidence with the shown source, note, capture date, and file metadata."))
                                .heldCaption()
                                .foregroundStyle(HeldColor.secondaryInk)
                        }
                    }
                    Text(L("Nothing is saved automatically. After saving, original evidence metadata is immutable; deletion requires separate confirmation."))
                        .heldCaption()
                        .foregroundStyle(HeldColor.secondaryInk)
                }
            }
            .navigationTitle(draft.attachment == nil ? L("Add evidence") : L("Review evidence"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) {
                        onCancel(draft)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Save evidence"), action: save)
                        .disabled(!draft.confirmed || isRecognizingText)
                }
            }
            .alert(L("Evidence needs attention"), isPresented: errorPresented) {
                Button(L("OK")) { errorMessage = nil }
            } message: {
                Text(L(errorMessage ?? "Unknown error"))
            }
        }
    }

    private var canRecognizeImageText: Bool {
        guard let attachment = draft.attachment else { return false }
        return attachment.mimeType.hasPrefix("image/") && attachmentStore != nil
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func recognizeImageText() {
        guard let attachment = draft.attachment, let attachmentStore else { return }
        guard attachment.fileSize <= 50 * 1_024 * 1_024 else {
            errorMessage = L("This image is too large for on-device text recognition. You can still save it as evidence and enter a note manually.")
            return
        }

        isRecognizingText = true
        ocrMessage = nil
        Task {
            do {
                let url = try attachmentStore.url(forRelativePath: attachment.relativePath)
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                let result = try await OCREngine().recognizeText(data: data)
                if result.fullText.isEmpty {
                    ocrMessage = L("No text was recognized. Your existing note is unchanged; enter or edit it manually.")
                } else {
                    draft.note = result.fullText
                    ocrMessage = result.limitations
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isRecognizingText = false
        }
    }

    private func save() {
        do {
            _ = try OrderDetailValidation.require(draft.title, field: "Evidence title")
            if draft.attachment == nil {
                _ = try OrderDetailValidation.require(draft.referenceFilename, field: L("Reference filename"))
            }
            try onSave(draft)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Immutable evidence details and deletion

struct EvidenceDetailSheet: View {
    @EnvironmentObject private var localization: LocalizationCenter
    let evidence: Evidence
    let attachmentStore: AttachmentStore?
    let onDelete: (Evidence) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var preview: OrderFilePreview?
    @State private var deleteConfirmationPresented = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HeldSpacing.large) {
                    VStack(alignment: .leading, spacing: HeldSpacing.small) {
                        Label(localizedEvidenceKindLabel(evidence.kind), systemImage: evidence.kind.symbolName)
                            .foregroundStyle(HeldColor.accent)
                        Text(evidence.title)
                            .heldDisplay(size: 30)
                            .foregroundStyle(HeldColor.ink)
                        Label(L("Original metadata is locked"), systemImage: "lock.fill")
                            .heldCaption()
                            .foregroundStyle(HeldColor.secondaryInk)
                    }

                    if evidence.localRelativePath != nil {
                        EvidenceThumbnail(evidence: evidence, attachmentStore: attachmentStore, pixelSize: 1_200)
                            .frame(maxWidth: .infinity)
                            .frame(height: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    HeldCard {
                        VStack(alignment: .leading, spacing: HeldSpacing.medium) {
                            OrderDetailMetadataRow(title: L("Filename"), value: evidence.filename)
                            OrderDetailMetadataRow(title: L("Source"), value: evidence.source.isEmpty ? L("Not recorded") : evidence.source)
                            OrderDetailMetadataRow(title: L("Captured at"), value: orderDetailDateTime(evidence.capturedAt))
                            OrderDetailMetadataRow(title: L("MIME type"), value: evidence.mimeType.isEmpty ? L("Not recorded") : evidence.mimeType)
                            OrderDetailMetadataRow(title: L("File size"), value: orderDetailFileSize(evidence.fileSize))
                            OrderDetailMetadataRow(title: L("SHA-256"), value: evidence.sha256?.isEmpty == false ? evidence.sha256! : L("Not recorded"), monospaced: true)
                        }
                    }

                    HeldCard {
                        VStack(alignment: .leading, spacing: HeldSpacing.small) {
                            Text(L("Note"))
                                .font(.headline)
                            Text(evidence.note.isEmpty ? L("No note recorded.") : evidence.note)
                                .heldBody()
                                .foregroundStyle(evidence.note.isEmpty ? HeldColor.secondaryInk : HeldColor.ink)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if evidence.localRelativePath != nil {
                        Button {
                            openPreview()
                        } label: {
                            Label(L("Preview original file"), systemImage: "quicklook")
                                .frame(maxWidth: .infinity)
                        }
                        .heldButtonStyle(.secondary)
                    }

                    Button(role: .destructive) {
                        deleteConfirmationPresented = true
                    } label: {
                        Label(L("Delete evidence"), systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .heldButtonStyle(.quiet)
                    .foregroundStyle(HeldColor.danger)
                }
                .padding(HeldSpacing.large)
            }
            .heldScreenBackground()
            .navigationTitle(L("Evidence"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                }
            }
            .sheet(item: $preview) { preview in
                OrderQuickLookSheet(preview: preview)
            }
            .alert(L("Delete this evidence?"), isPresented: $deleteConfirmationPresented) {
                Button(L("Cancel"), role: .cancel) {}
                Button(L("Delete evidence"), role: .destructive, action: delete)
            } message: {
                Text(L("The evidence record will be deleted. Any imported attachment will also be removed from Keyvow storage. This cannot be undone."))
            }
            .alert(L("Evidence action failed"), isPresented: errorPresented) {
                Button(L("OK")) { errorMessage = nil }
            } message: {
                Text(L(errorMessage ?? "Unknown error"))
            }
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func openPreview() {
        guard let path = evidence.localRelativePath, let attachmentStore else {
            errorMessage = OrderDetailValidationError.attachmentStoreUnavailable.localizedDescription
            return
        }
        do {
            let url = try attachmentStore.url(forRelativePath: path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                errorMessage = L("The original attachment is missing from Keyvow storage.")
                return
            }
            preview = OrderFilePreview(url: url, title: evidence.title)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete() {
        do {
            try onDelete(evidence)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - QuickLook

struct OrderQuickLookSheet: UIViewControllerRepresentable {
    let preview: OrderFilePreview

    func makeCoordinator() -> Coordinator {
        Coordinator(preview: preview)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        controller.navigationItem.title = preview.title
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        context.coordinator.preview = preview
        controller.reloadData()
    }

    @MainActor
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var preview: OrderFilePreview

        init(preview: OrderFilePreview) {
            self.preview = preview
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            preview.url as NSURL
        }
    }
}

// MARK: - Live text capture

struct OrderLiveTextSheet: View {
    @EnvironmentObject private var localization: LocalizationCenter
    let onUseText: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var recognizedText = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if DocumentScanner.isSupported {
                    DocumentScanner(
                        onText: { text in
                            if recognizedText.isEmpty {
                                recognizedText = text
                            } else if !recognizedText.contains(text) {
                                recognizedText += "\n" + text
                            }
                        },
                        onError: { errorMessage = $0 }
                    )
                    .frame(minHeight: 300)
                    .accessibilityLabel(L("Live text scanner"))
                } else {
                    OrderDetailCallout(
                        title: L("Live text unavailable"),
                        message: DocumentScanner.unavailableReason,
                        symbolName: "camera.metering.unknown",
                        tone: .warning
                    )
                    .padding(HeldSpacing.large)
                }

                VStack(alignment: .leading, spacing: HeldSpacing.small) {
                    Text(L("Review recognized text"))
                        .font(.headline)
                    TextEditor(text: $recognizedText)
                        .frame(minHeight: 140)
                        .padding(HeldSpacing.small)
                        .background(HeldColor.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(HeldColor.separator)
                        }
                        .accessibilityLabel(L("Editable recognized evidence text"))
                    Text(L("Recognition can be wrong. Edit the text before continuing; nothing is saved automatically."))
                        .heldCaption()
                        .foregroundStyle(HeldColor.secondaryInk)
                }
                .padding(HeldSpacing.large)
            }
            .heldScreenBackground()
            .navigationTitle(L("Scan live text"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Use in evidence")) {
                        onUseText(recognizedText)
                    }
                    .disabled(OrderDetailValidation.trimmed(recognizedText).isEmpty)
                }
            }
            .alert(L("Scanner"), isPresented: errorPresented) {
                Button(L("OK")) { errorMessage = nil }
            } message: {
                Text(L(errorMessage ?? "Unknown error"))
            }
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }
}
