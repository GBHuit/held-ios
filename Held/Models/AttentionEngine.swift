import Foundation

enum AttentionEngine {
    private static let day: TimeInterval = 24 * 60 * 60

    static func attention(
        orders: [HeldOrder],
        settings: AppSettings,
        now: Date = Date()
    ) -> [OrderAttention] {
        var result: [OrderAttention] = []

        for order in orders where order.isActive {
            var reasons: [AttentionReason] = []
            var seen = Set<AttentionReasonKind>()

            func addReason(_ reason: AttentionReason) {
                guard seen.insert(reason.kind).inserted else { return }
                reasons.append(reason)
            }

            if let estimateEnd = order.estimateEnd,
               order.fulfillmentStatus != .delivered,
               estimateEnd < now {
                addReason(AttentionReason(
                    kind: .estimate,
                    title: "Original estimate has passed",
                    description: "\(order.estimateText) Last promised date: \(formatDate(estimateEnd))."
                ))
            }

            if let nextCheckAt = order.nextCheckAt, nextCheckAt <= now {
                addReason(AttentionReason(
                    kind: .check,
                    title: "Check-in is due",
                    description: "A follow-up was scheduled for \(formatDate(nextCheckAt))."
                ))
            }

            let dueDeadline = order.reminders
                .filter { reminder in
                    guard reminder.kind == .deadline, reminder.enabled else { return false }
                    let leadDays = max(0, reminder.leadDays)
                    let leadEnd = now.addingTimeInterval(TimeInterval(leadDays) * day)
                    return reminder.triggerAt <= leadEnd
                }
                .sorted { $0.triggerAt < $1.triggerAt }
                .first

            if let dueDeadline {
                addReason(AttentionReason(
                    kind: .deadline,
                    title: "Deadline is approaching",
                    description: "\(dueDeadline.label) — \(formatDate(dueDeadline.triggerAt))."
                ))
            }

            let staleAge = now.timeIntervalSince(order.lastUserUpdateAt)
            if staleAge >= TimeInterval(max(0, settings.staleDays)) * day {
                addReason(AttentionReason(
                    kind: .stale,
                    title: "No recent update",
                    description: "No user update has been recorded since \(formatDate(order.lastUserUpdateAt))."
                ))
            }

            if order.fulfillmentStatus == .partiallyShipped {
                let outstanding = order.items.filter {
                    $0.deliveredQuantity < $0.quantity && $0.status != .delivered
                }.count
                let lineItemText = outstanding == 1 ? "line item is" : "line items are"
                addReason(AttentionReason(
                    kind: .partial,
                    title: "Partial delivery needs review",
                    description: "\(outstanding) \(lineItemText) still outstanding; the order is not complete."
                ))
            }

            if !reasons.isEmpty {
                result.append(OrderAttention(order: order, reasons: reasons))
            }
        }

        return result
    }

    static func funds(orders: [HeldOrder]) -> [CurrencyFunds] {
        var funds: [CurrencyFunds] = []
        var indicesByCurrency: [String: Int] = [:]

        for order in orders {
            let currency = order.currencyCode.rawValue
            let index: Int
            if let existingIndex = indicesByCurrency[currency] {
                index = existingIndex
            } else {
                index = funds.count
                indicesByCurrency[currency] = index
                funds.append(CurrencyFunds(currency: currency))
            }

            let deliveredMinor: Int64
            switch order.fulfillmentStatus {
            case .delivered:
                deliveredMinor = order.amountMinor
            case .partiallyShipped:
                // If allocation is incomplete, keep the full value pending.
                deliveredMinor = exactPartialDeliveredMinor(order: order) ?? 0
            case .ordered, .inProduction, .shipped:
                deliveredMinor = 0
            }

            funds[index].totalMinor += order.amountMinor
            funds[index].deliveredMinor += deliveredMinor
            funds[index].pendingMinor += order.amountMinor - deliveredMinor
        }

        return funds
    }

    private static func exactPartialDeliveredMinor(order: HeldOrder) -> Int64? {
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
            let quantity = item.quantity
            let deliveredQuantity = item.status == .delivered
                ? quantity
                : min(quantity, max(0, item.deliveredQuantity))

            // Decimal plus .plain reproduces Math.round for nonnegative values.
            var unrounded = Decimal(amountMinor)
                * Decimal(deliveredQuantity)
                / Decimal(quantity)
            var rounded = Decimal()
            NSDecimalRound(&rounded, &unrounded, 0, .plain)
            deliveredMinor += NSDecimalNumber(decimal: rounded).int64Value
        }

        return min(order.amountMinor, max(0, deliveredMinor))
    }
}
