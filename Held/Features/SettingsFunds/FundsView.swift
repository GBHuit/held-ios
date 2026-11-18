import SwiftUI
import SwiftData

/// A per-currency account of order value. No exchange rates or cross-currency
/// totals are introduced here; the figures mirror AttentionEngine.funds.
public struct FundsView: View {
    @Query(sort: \HeldOrder.orderedAt, order: .reverse) private var orders: [HeldOrder]
    @State private var expandedCurrencies: Set<String> = []

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: HeldSpacing.large) {
                    editorialHeader

                    if funds.isEmpty {
                        HeldEmptyView(
                            icon: "shippingbox",
                            title: "Nothing to account for yet",
                            message: "When you add an order, Held will show its pending and delivered value in the order’s own currency."
                        )
                        .frame(minHeight: 360)
                    } else {
                        ForEach(funds, id: \.currency) { fund in
                            currencyCard(fund)
                        }

                        allocationExplanation
                    }
                }
                .padding(.horizontal, HeldSpacing.medium)
                .padding(.vertical, HeldSpacing.large)
            }
            .heldScreenBackground()
            .heldNavigationTitle("Funds")
        }
    }

    private var funds: [CurrencyFunds] {
        AttentionEngine.funds(orders: orders).sorted { $0.currency < $1.currency }
    }

    private var editorialHeader: some View {
        VStack(alignment: .leading, spacing: HeldSpacing.small) {
            Text(funds.count > 1 ? "Every currency, kept distinct." : "What’s still on its way.")
                .heldDisplay(size: 30)
                .foregroundStyle(HeldColor.ink)
                .fixedSize(horizontal: false, vertical: true)

            if funds.isEmpty {
                Text("A quiet ledger for money committed to orders and value already received.")
                    .heldBody()
                    .foregroundStyle(HeldColor.secondaryInk)
            } else {
                Text("\(orders.count) \(orders.count == 1 ? "order" : "orders") across \(funds.count) \(funds.count == 1 ? "currency" : "currencies"). Amounts are never converted or added across currencies.")
                    .heldBody()
                    .foregroundStyle(HeldColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func currencyCard(_ fund: CurrencyFunds) -> some View {
        let rows = orderRows(for: fund.currency)
        let ratio = progressRatio(delivered: fund.deliveredMinor, total: fund.totalMinor)
        let isExpanded = Binding(
            get: { expandedCurrencies.contains(fund.currency) },
            set: { expanded in
                if expanded {
                    expandedCurrencies.insert(fund.currency)
                } else {
                    expandedCurrencies.remove(fund.currency)
                }
            }
        )

        return HeldCard(padding: HeldSpacing.medium) {
            VStack(alignment: .leading, spacing: HeldSpacing.medium) {
                HStack(alignment: .firstTextBaseline, spacing: HeldSpacing.medium) {
                    VStack(alignment: .leading, spacing: HeldSpacing.extraSmall) {
                        Text(fund.currency)
                            .font(.headline)
                            .foregroundStyle(HeldColor.accent)
                        Text(formatMoney(minor: fund.totalMinor, currency: fund.currency))
                            .heldDisplay(size: 28)
                            .foregroundStyle(HeldColor.ink)
                            .accessibilityLabel("Total \(formatMoney(minor: fund.totalMinor, currency: fund.currency))")
                    }
                    Spacer(minLength: HeldSpacing.small)
                    HeldBadge(
                        text: "\(rows.count) \(rows.count == 1 ? "order" : "orders")",
                        tone: .neutral
                    )
                }

                HStack(alignment: .top, spacing: HeldSpacing.medium) {
                    valueBlock(
                        title: "Pending",
                        minor: fund.pendingMinor,
                        currency: fund.currency,
                        color: HeldColor.amber
                    )
                    valueBlock(
                        title: "Delivered",
                        minor: fund.deliveredMinor,
                        currency: fund.currency,
                        color: HeldColor.accent
                    )
                }

                if fund.refundedMinor > 0 || fund.cancelledMinor > 0 {
                    HStack(alignment: .top, spacing: HeldSpacing.medium) {
                        valueBlock(
                            title: "Refunded",
                            minor: fund.refundedMinor,
                            currency: fund.currency,
                            color: HeldColor.secondaryInk
                        )
                        valueBlock(
                            title: "Cancelled",
                            minor: fund.cancelledMinor,
                            currency: fund.currency,
                            color: HeldColor.terracotta
                        )
                    }
                }

                if fund.refundPendingMinor > 0 {
                    Label(
                        "Refund or dispute pending: \(formatMoney(minor: fund.refundPendingMinor, currency: fund.currency)). This is unresolved order value, not a confirmed refund.",
                        systemImage: "arrow.uturn.backward.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(HeldColor.amber)
                    .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: HeldSpacing.small) {
                    HStack {
                        Text("Delivered value")
                            .font(.subheadline)
                            .foregroundStyle(HeldColor.secondaryInk)
                        Spacer()
                        Text(fund.totalMinor == 0 ? "No value recorded" : percentage(ratio))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(HeldColor.ink)
                    }
                    HeldProgressView(value: ratio)
                        .accessibilityLabel("Delivered value in \(fund.currency)")
                        .accessibilityValue(percentage(ratio))
                }

                DisclosureGroup(isExpanded: isExpanded) {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            if index > 0 {
                                Divider()
                                    .overlay(HeldColor.separator)
                                    .padding(.vertical, HeldSpacing.extraSmall)
                            }
                            orderRow(row)
                                .padding(.vertical, HeldSpacing.small)
                        }
                    }
                    .padding(.top, HeldSpacing.small)
                } label: {
                    Text("Order breakdown")
                        .font(.headline)
                        .foregroundStyle(HeldColor.accent)
                }
                .tint(HeldColor.accent)
            }
        }
    }

    private func valueBlock(title: String, minor: Int64, currency: String, color: Color) -> some View {
        let icon: String
        switch title {
        case "Pending": icon = "clock"
        case "Refunded": icon = "arrow.uturn.backward.circle"
        case "Cancelled": icon = "xmark.circle"
        default: icon = "checkmark.circle"
        }

        return VStack(alignment: .leading, spacing: HeldSpacing.extraSmall) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.medium))
                .foregroundStyle(color)
            Text(formatMoney(minor: minor, currency: currency))
                .font(.title3.weight(.semibold))
                .foregroundStyle(HeldColor.ink)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func orderRow(_ row: FundsOrderRow) -> some View {
        VStack(alignment: .leading, spacing: HeldSpacing.small) {
            HStack(alignment: .top, spacing: HeldSpacing.small) {
                VStack(alignment: .leading, spacing: HeldSpacing.extraSmall) {
                    Text(row.order.title)
                        .font(.headline)
                        .foregroundStyle(HeldColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if !row.order.vendor.isEmpty {
                        Text(row.order.vendor)
                            .heldCaption()
                            .foregroundStyle(HeldColor.secondaryInk)
                    }
                }
                Spacer(minLength: HeldSpacing.small)
                VStack(alignment: .trailing, spacing: HeldSpacing.extraSmall) {
                    HeldBadge(text: row.order.fulfillmentStatus.displayLabel, tone: badgeTone(for: row.order))
                    if row.order.resolutionStatus != .none {
                        HeldBadge(text: row.order.resolutionStatus.displayLabel, tone: .warning)
                    }
                }
            }

            Text("Charged \(formatMoney(minor: row.value.totalMinor, currency: row.order.currencyCode))")
                .font(.body.weight(.semibold))
                .foregroundStyle(HeldColor.ink)

            VStack(alignment: .leading, spacing: HeldSpacing.extraSmall) {
                Text("Pending \(formatMoney(minor: row.value.pendingMinor, currency: row.order.currencyCode))")
                Text("Net delivered \(formatMoney(minor: row.value.deliveredMinor, currency: row.order.currencyCode))")
                if row.value.refundedMinor > 0 {
                    Text("Refunded \(formatMoney(minor: row.value.refundedMinor, currency: row.order.currencyCode))")
                }
                if row.value.cancelledMinor > 0 {
                    Text("Cancelled \(formatMoney(minor: row.value.cancelledMinor, currency: row.order.currencyCode))")
                }
                if row.value.refundPendingMinor > 0 {
                    Text("Refund or dispute pending \(formatMoney(minor: row.value.refundPendingMinor, currency: row.order.currencyCode))")
                        .foregroundStyle(HeldColor.amber)
                }
            }
            .font(.caption)
            .foregroundStyle(HeldColor.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: HeldSpacing.extraSmall) {
                HeldProgressView(value: row.order.progress)
                    .accessibilityLabel("Fulfillment progress for \(row.order.title)")
                    .accessibilityValue(percentage(row.order.progress))
                Text("Fulfillment \(percentage(row.order.progress))")
                    .heldCaption()
                    .foregroundStyle(HeldColor.secondaryInk)
            }

            if row.value.usesDeliveryFallback {
                Label(
                    "Item allocations are missing or incomplete. Unknown delivery value remains pending; only explicit item refunds or cancellations are counted.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(HeldColor.amber)
                .fixedSize(horizontal: false, vertical: true)
            } else if !row.order.items.isEmpty && row.value.deliveredMinor > 0 {
                Label(
                    "Net delivered value is prorated from exact item amounts and quantities, excluding refunded and cancelled lines.",
                    systemImage: "checklist"
                )
                .font(.caption)
                .foregroundStyle(HeldColor.accent)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, HeldSpacing.extraSmall)
        .accessibilityElement(children: .combine)
    }

    private var allocationExplanation: some View {
        HeldCard(padding: HeldSpacing.medium) {
            VStack(alignment: .leading, spacing: HeldSpacing.small) {
                Label("How Held counts value", systemImage: "text.book.closed")
                    .font(.headline)
                    .foregroundStyle(HeldColor.accent)
                    .accessibilityAddTraits(.isHeader)

                Text("Charged is the gross order amount. A cancelled or fully refunded order moves its full amount to that category. For partial outcomes, only line items explicitly marked refunded or cancelled contribute their recorded line amounts.")
                    .heldBody()
                    .foregroundStyle(HeldColor.secondaryInk)

                Text("Net delivered value excludes confirmed refunds and cancellations. Delivered orders without line items use the remaining order amount. With items, Held prorates delivered quantities only when every line has a nonnegative amount and all line amounts add up exactly to the order total; otherwise unknown value stays pending.")
                    .heldBody()
                    .foregroundStyle(HeldColor.secondaryInk)

                Text("Refund requested or disputed shows the remaining unresolved order value separately. It is not a confirmed refund and can coexist with delivered value because no requested refund amount is stored.")
                    .heldBody()
                    .foregroundStyle(HeldColor.secondaryInk)

                Text("Each currency has its own ledger. Held never invents an exchange rate, refund amount, or combined total.")
                    .heldBody()
                    .foregroundStyle(HeldColor.secondaryInk)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func orderRows(for currency: String) -> [FundsOrderRow] {
        orders
            .filter { $0.currencyCode.rawValue == currency }
            .map { order in
                FundsOrderRow(order: order, value: AttentionEngine.fundsBreakdown(for: order))
            }
            .sorted { $0.order.orderedAt > $1.order.orderedAt }
    }

    private func progressRatio(delivered: Int64, total: Int64) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(delivered) / Double(total)))
    }

    private func percentage(_ value: Double) -> String {
        let clamped = min(1, max(0, value.isFinite ? value : 0))
        return "\(Int((clamped * 100).rounded()))%"
    }

    private func badgeTone(for order: HeldOrder) -> BadgeTone {
        switch order.fulfillmentStatus {
        case .delivered:
            return .success
        case .partiallyShipped:
            return .warning
        case .shipped:
            return .info
        case .ordered, .inProduction:
            return .neutral
        }
    }
}

private struct FundsOrderRow: Identifiable {
    let order: HeldOrder
    let value: OrderFundsBreakdown

    var id: String { order.id }
}
