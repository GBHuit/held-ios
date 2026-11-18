import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class ShareImportModel: ObservableObject {
    @Published var sourceURL = ""
    @Published var sharedText = ""
    @Published var errorMessage: String?
    @Published var isSaving = false

    private let extensionContext: NSExtensionContext?

    init(extensionContext: NSExtensionContext?) {
        self.extensionContext = extensionContext
    }

    var canSave: Bool {
        !isSaving && (!sourceURL.isEmpty || !sharedText.isEmpty)
    }

    func load() {
        Task { await loadAttachments() }
    }

    func cancel() {
        let error = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        extensionContext?.cancelRequest(withError: error)
    }

    func save() {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        do {
            let payload = PendingSharePayload(
                sourceURL: sourceURL.isEmpty ? nil : sourceURL,
                sharedText: sharedText.isEmpty ? nil : sharedText
            )
            try PendingShareWriter.write(payload)
            extensionContext?.completeRequest(returningItems: nil)
        } catch {
            errorMessage = L("The shared item could not be queued. %@", error.localizedDescription)
            isSaving = false
        }
    }

    private func loadAttachments() async {
        let providers = extensionContext?.inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] } ?? []

        var foundURL: String?
        var textParts: [String] = []
        for provider in providers {
            if foundURL == nil, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                if let item = try? await Self.loadItem(from: provider, typeIdentifier: UTType.url.identifier) {
                    foundURL = Self.httpsURLString(from: item)
                }
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                if let item = try? await Self.loadItem(from: provider, typeIdentifier: UTType.plainText.identifier),
                   let text = Self.text(from: item),
                   !textParts.contains(text) {
                    textParts.append(text)
                }
            }
        }

        let combinedText = textParts.joined(separator: "\n")
        if foundURL == nil {
            let trimmed = combinedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = URL(string: trimmed), url.scheme?.lowercased() == "https", url.host != nil {
                foundURL = url.absoluteString
                textParts = []
            }
        }

        sourceURL = foundURL ?? ""
        sharedText = textParts.joined(separator: "\n")
        if !canSave {
            errorMessage = L("Share an https link or some text to add it to Keyvow.")
        }
    }

    private static func loadItem(
        from provider: NSItemProvider,
        typeIdentifier: String
    ) async throws -> NSSecureCoding? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: item)
                }
            }
        }
    }

    private static func httpsURLString(from item: NSSecureCoding?) -> String? {
        let candidate: URL?
        switch item {
        case let url as URL: candidate = url
        case let string as String: candidate = URL(string: string)
        case let data as Data: candidate = URL(dataRepresentation: data, relativeTo: nil)
        default: candidate = nil
        }
        guard let candidate,
              candidate.scheme?.lowercased() == "https",
              candidate.host != nil else { return nil }
        return candidate.absoluteString
    }

    private static func text(from item: NSSecureCoding?) -> String? {
        let value: String?
        switch item {
        case let string as String: value = string
        case let attributed as NSAttributedString: value = attributed.string
        case let data as Data: value = String(data: data, encoding: .utf8)
        default: value = nil
        }
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : String(trimmed.prefix(100_000))
    }
}

final class ShareViewController: UIViewController {
    private var model: ShareImportModel?

    override func viewDidLoad() {
        super.viewDidLoad()
        let model = ShareImportModel(extensionContext: extensionContext)
        self.model = model
        let content = ShareImportView(model: model)
        let hostingController = UIHostingController(rootView: content.environmentObject(ShareLocalizationCenter.shared))
        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hostingController.didMove(toParent: self)
        model.load()
    }
}

private struct ShareImportView: View {
    @EnvironmentObject private var localization: ShareLocalizationCenter
    @ObservedObject var model: ShareImportModel

    var body: some View {
        NavigationStack {
            Form {
                Section(L("Shared with Keyvow")) {
                    if !model.sourceURL.isEmpty {
                        Label(model.sourceURL, systemImage: "link")
                            .textSelection(.enabled)
                    }
                    if !model.sharedText.isEmpty {
                        Text(model.sharedText)
                            .lineLimit(3...10)
                            .textSelection(.enabled)
                    }
                    if model.sourceURL.isEmpty && model.sharedText.isEmpty && model.errorMessage == nil {
                        HStack {
                            ProgressView()
                            Text(L("Reading shared content…"))
                        }
                        .accessibilityElement(children: .combine)
                    }
                }

                Section {
                    Text(L("This queues the shared details on this device. You will review them before creating an order in Keyvow."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let errorMessage = model.errorMessage {
                        Text(L(errorMessage))
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .navigationTitle(L("Add to Keyvow"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel"), action: model.cancel)
                        .frame(minWidth: 44, minHeight: 44)
                        .disabled(model.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Queue"), action: model.save)
                        .frame(minWidth: 44, minHeight: 44)
                        .disabled(!model.canSave)
                }
            }
        }
    }
}
