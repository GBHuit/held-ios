import SwiftUI

struct HomeOrderCard: View {
    let order: HeldOrder

    @EnvironmentObject private var localization: LocalizationCenter
    var showsProgress = true
    var showsChevron = true

    private var statusTone: BadgeTone {
        if order.resolutionStatus == .disputed || order.resolutionStatus == .refundRequested {
            return .warning
        }
        switch order.fulfillmentStatus {
        case .delivered:
            return .success
        case .shipped, .partiallyShipped:
            return .info
        case .ordered, .inProduction:
            return .neutral
        }
    }

    private var secondaryLine: String {
        let number = order.orderNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        return number.isEmpty ? order.vendor : "\(order.vendor) · #\(number)"
    }

    var body: some View {
        HeldCard(padding: HeldSpacing.medium) {
            VStack(alignment: .leading, spacing: HeldSpacing.small) {
                HStack(alignment: .top, spacing: HeldSpacing.medium) {
                    Text(order.title)
                        .font(.headline)
                        .foregroundStyle(HeldColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: HeldSpacing.small)
                    if showsChevron {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(HeldColor.secondaryInk)
                            .padding(.top, 3)
                            .accessibilityHidden(true)
                    }
                }

                Text(secondaryLine)
                    .heldCaption()
                    .foregroundStyle(HeldColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: HeldSpacing.small) {
                    HStack(alignment: .firstTextBaseline, spacing: HeldSpacing.small) {
                        HeldBadge(text: order.fulfillmentStatus.displayLabel, tone: statusTone)
                        if order.resolutionStatus != .none {
                            HeldBadge(text: order.resolutionStatus.displayLabel, tone: .warning)
                        }
                    }
                    Text(localization.money(minor: order.amountMinor, currency: order.currencyCode))
                        .heldCaption()
                        .foregroundStyle(HeldColor.ink)
                }

                if showsProgress {
                    HeldProgressView(value: order.progress)
                        .padding(.top, HeldSpacing.extraSmall)

                    HStack {
                        Text(L("Ordered %@", localization.date(order.orderedAt)))
                        Spacer()
                        Text(L("%1$lld%% complete", Int64((order.progress * 100).rounded())))
                    }
                    .heldCaption()
                    .foregroundStyle(HeldColor.secondaryInk)
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint(L("Opens order details"))
    }

    private var accessibilityDescription: String {
        var parts = [
            order.title,
            secondaryLine,
            order.fulfillmentStatus.displayLabel,
            localization.money(minor: order.amountMinor, currency: order.currencyCode),
            L("Ordered %@", localization.date(order.orderedAt))
        ]
        if order.resolutionStatus != .none {
            parts.append(order.resolutionStatus.displayLabel)
        }
        if showsProgress {
            parts.append(L("%1$lld percent complete", Int64((order.progress * 100).rounded())))
        }
        return parts.joined(separator: ", ")
    }
}

struct HomeOrdersMessage: View {
    let title: String
    let message: String
    var systemImage = "checkmark.circle"

    var body: some View {
        HeldCard {
            HStack(alignment: .top, spacing: HeldSpacing.medium) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(HeldColor.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: HeldSpacing.extraSmall) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(HeldColor.ink)
                    Text(message)
                        .heldBody()
                        .foregroundStyle(HeldColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

enum HomeOrdersText {
    static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
