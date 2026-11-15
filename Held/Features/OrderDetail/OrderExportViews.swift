import SwiftUI
import UIKit

struct OrderExportPreviewSheet: View {
    let order: HeldOrder
    let kind: OrderExportKind
    let onExport: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var privacyConfirmed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HeldSpacing.large) {
                    VStack(alignment: .leading, spacing: HeldSpacing.small) {
                        Image(systemName: kind.symbolName)
                            .font(.largeTitle)
                            .foregroundStyle(HeldColor.accent)
                            .accessibilityHidden(true)
                        Text(kind.title)
                            .heldDisplay(size: 30)
                            .foregroundStyle(HeldColor.ink)
                        Text(kind.subtitle)
                            .heldBody()
                            .foregroundStyle(HeldColor.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HeldCard {
                        VStack(alignment: .leading, spacing: HeldSpacing.medium) {
                            Text("Export preview")
                                .font(.headline)
                            OrderDetailMetadataRow(title: "Order", value: order.title)
                            OrderDetailMetadataRow(title: "Vendor", value: order.vendor.isEmpty ? "Not recorded" : order.vendor)
                            OrderDetailMetadataRow(title: "Line items", value: String(order.items.count))
                            OrderDetailMetadataRow(title: "Milestones", value: String(order.milestones.count))
                            OrderDetailMetadataRow(title: "Evidence records", value: String(order.evidence.count))
                            if kind == .evidenceZIP {
                                OrderDetailMetadataRow(
                                    title: "Attached files",
                                    value: String(order.evidence.filter { $0.localRelativePath != nil }.count)
                                )
                            }
                        }
                    }

                    OrderDetailCallout(
                        title: "Private data included",
                        message: privacyMessage,
                        symbolName: "hand.raised.fill",
                        tone: .warning
                    )

                    Toggle(isOn: $privacyConfirmed) {
                        Text("I understand and want to create this export")
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityHint("Required before creating a file that can be shared outside Held")

                    Button {
                        onExport()
                        dismiss()
                    } label: {
                        Label("Create & share export", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .heldButtonStyle(.primary)
                    .disabled(!privacyConfirmed)
                }
                .padding(HeldSpacing.large)
            }
            .heldScreenBackground()
            .navigationTitle("Export order")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var privacyMessage: String {
        switch kind {
        case .json:
            return "This JSON contains order, payment, source URL, notes, tracking, reminder, evidence metadata, and app settings. Sharing it can expose private purchase and dispute information."
        case .csv:
            return "This CSV contains order, payment, source URL, notes, tracking, and line-item details. Sharing it can expose private purchase information."
        case .pdf:
            return "This PDF contains order and payment details plus evidence sources, notes, filenames, capture dates, and checksums. Review the recipient before sharing."
        case .evidenceZIP:
            return "This ZIP contains order, payment, source, and evidence metadata together with original attachment files. Treat it as sensitive private data."
        }
    }
}

/// Local to OrderDetail so it cannot collide with the app-wide settings ShareSheet.
struct OrderShareSheet: UIViewControllerRepresentable {
    let item: OrderShareItem

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: [item.url],
            applicationActivities: nil
        )
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
