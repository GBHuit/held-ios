import SwiftUI
import UIKit

struct OrderExportPreviewSheet: View {
    @EnvironmentObject private var localization: LocalizationCenter
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
                            Text(L("Export preview"))
                                .font(.headline)
                            OrderDetailMetadataRow(title: L("Order"), value: order.title)
                            OrderDetailMetadataRow(title: L("Vendor"), value: order.vendor.isEmpty ? L("Not recorded") : order.vendor)
                            OrderDetailMetadataRow(title: L("Line items"), value: String(order.items.count))
                            OrderDetailMetadataRow(title: L("Milestones"), value: String(order.milestones.count))
                            OrderDetailMetadataRow(title: L("Evidence records"), value: String(order.evidence.count))
                            if kind == .evidenceZIP {
                                OrderDetailMetadataRow(
                                    title: L("Attached files"),
                                    value: String(order.evidence.filter { $0.localRelativePath != nil }.count)
                                )
                            }
                        }
                    }

                    OrderDetailCallout(
                        title: L("Private data included"),
                        message: privacyMessage,
                        symbolName: "hand.raised.fill",
                        tone: .warning
                    )

                    Toggle(isOn: $privacyConfirmed) {
                        Text(L("I understand and want to create this export"))
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityHint(L("Required before creating a file that can be shared outside Keyvow"))

                    Button {
                        onExport()
                        dismiss()
                    } label: {
                        Label(L("Create & share export"), systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .heldButtonStyle(.primary)
                    .disabled(!privacyConfirmed)
                }
                .padding(HeldSpacing.large)
            }
            .heldScreenBackground()
            .navigationTitle(L("Export order"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) { dismiss() }
                }
            }
        }
    }

    private var privacyMessage: String {
        switch kind {
        case .json:
            return L("This JSON contains order, payment, source URL, notes, tracking, reminder, evidence metadata, and app settings. Sharing it can expose private purchase and dispute information.")
        case .csv:
            return L("This CSV contains order, payment, source URL, notes, tracking, and line-item details. Sharing it can expose private purchase information.")
        case .pdf:
            return L("This PDF contains order and payment details plus evidence sources, notes, filenames, capture dates, and checksums. Review the recipient before sharing.")
        case .evidenceZIP:
            return L("This ZIP contains order, payment, source, and evidence metadata together with original attachment files. Treat it as sensitive private data.")
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
