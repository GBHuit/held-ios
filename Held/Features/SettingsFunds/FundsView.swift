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
        VStack(alignment: .leading, spacing: HeldSpacing.extraSmall) {
            Label(title, systemImage: title == "Pending" ? "clock" : "checkmark.circle")
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
                HeldBadge(text: row.order.fulfillmentStatus.displayLabel, tone: badgeTone(for: row.order))
            }

            Text(formatMoney(minor: row.order.amountMinor, currency: row.order.currencyCode))
                .font(.body.weight(.semibold))
                .foregroundStyle(HeldColor.ink)

            HStack(alignment: .top, spacing: HeldSpacing.medium) {
                Text("Pending \(formatMoney(minor: row.pendingMinor, currency: row.order.currencyCode))")
                Text("Delivered \(formatMoney(minor: row.deliveredMinor, currency: row.order.currencyCode))")
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

            if row.usesPartialFallback {
                Label(
                    "Item allocations are missing or incomplete, so the full order value remains pending.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(HeldColor.amber)
                .fixedSize(horizontal: false, vertical: true)
            } else if row.order.fulfillmentStatus == .partiallyShipped {
                Label(
                    "Delivered value is prorated from exact item amounts and delivered quantities.",
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

                Text("Delivered orders count at their full order amount. Ordered, in-production, and shipped orders remain pending until delivery.")
                    .heldBody()
                    .foregroundStyle(HeldColor.secondaryInk)

                Text("For a partially shipped order, Held uses item amounts only when every line has a nonnegative amount and those amounts add up exactly to the order total. Delivered quantities are prorated per line. If that allocation is incomplete, the entire order amount stays pending rather than guessing.")
                    .heldBody()
                    .foregroundStyle(HeldColor.secondaryInk)

                Text("Each currency has its own ledger. Held never invents an exchange rate or a combined total.")
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
                let delivered = deliveredMinor(for: order)
                return FundsOrderRow(
                    order: order,
                    deliveredMinor: delivered,
                    pendingMinor: order.amountMinor - delivered,
                    usesPartialFallback: order.fulfillmentStatus == .partiallyShipped && exactPartialDeliveredMinor(order: order) == nil
                )
            }
            .sorted { $0.order.orderedAt > $1.order.orderedAt }
    }

    /// Matches AttentionEngine's public funds calculation, including its
    /// conservative fallback for partially allocated orders.
    private func deliveredMinor(for order: HeldOrder) -> Int64 {
        switch order.fulfillmentStatus {
        case .delivered:
            return order.amountMinor
        case .partiallyShipped:
            return exactPartialDeliveredMinor(order: order) ?? 0
        case .ordered, .inProduction, .shipped:
            return 0
        }
    }

    private func exactPartialDeliveredMinor(order: HeldOrder) -> Int64? {
        guard !order.items.isEmpty else { return nil }

        var allocatedTotal: Int64 = 0
        for item in order.items {
            guard let amountMinor = item.amountMinor,
                  amountMinor >= 0,
                  item.quantity > 0 else {
                return nil
            }
            allocatedTotal += amountMinor
        }
        guard allocatedTotal == order.amountMinor else { return nil }

        var deliveredMinor: Int64 = 0
        for item in order.items {
            guard let amountMinor = item.amountMinor else { return nil }
            let deliveredQuantity = item.status == .delivered
                ? item.quantity
                : min(item.quantity, max(0, item.deliveredQuantity))
            var unrounded = Decimal(amountMinor)
                * Decimal(deliveredQuantity)
                / Decimal(item.quantity)
            var rounded = Decimal()
            NSDecimalRound(&rounded, &unrounded, 0, .plain)
            deliveredMinor += NSDecimalNumber(decimal: rounded).int64Value
        }
        return min(order.amountMinor, max(0, deliveredMinor))
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
    let deliveredMinor: Int64
    let pendingMinor: Int64
    let usesPartialFallback: Bool

    var id: String { order.id }
}
