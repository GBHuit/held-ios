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
               Calendar.current.compare(now, to: estimateEnd, toGranularity: .day) == .orderedDescending {
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

            let trackableItems = order.items.filter {
                $0.quantity > 0 && $0.status != .cancelled && $0.status != .refunded
            }
            let totalUnits = trackableItems.reduce(0) { $0 + $1.quantity }
            let deliveredUnits = trackableItems.reduce(0) { result, item in
                let delivered = item.status == .delivered
                    ? item.quantity
                    : min(item.quantity, max(0, item.deliveredQuantity))
                return result + delivered
            }
            let outstandingItems = trackableItems.filter {
                let delivered = $0.status == .delivered
                    ? $0.quantity
                    : min($0.quantity, max(0, $0.deliveredQuantity))
                return delivered < $0.quantity
            }
            let hasShippedUnits = trackableItems.contains { $0.status == .shipped }
            if totalUnits > 0, deliveredUnits < totalUnits,
               deliveredUnits > 0 || hasShippedUnits {
                let outstandingUnits = totalUnits - deliveredUnits
                let lineItemText = outstandingItems.count == 1 ? "line item" : "line items"
                addReason(AttentionReason(
                    kind: .partial,
                    title: "Partial delivery needs review",
                    description: "\(outstandingUnits) units across \(outstandingItems.count) \(lineItemText) still outstanding; the order is not complete."
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

            let value = fundsBreakdown(for: order)
            funds[index].totalMinor += value.totalMinor
            funds[index].deliveredMinor += value.deliveredMinor
            funds[index].pendingMinor += value.pendingMinor
            funds[index].refundedMinor += value.refundedMinor
            funds[index].refundPendingMinor += value.refundPendingMinor
            funds[index].cancelledMinor += value.cancelledMinor
        }

        return funds
    }

    /// Confirmed refunds and cancellations are deducted from net delivered value.
    /// An unresolved refund is shown separately because no requested amount field
    /// exists and a delivered order can still be awaiting its refund outcome.
    static func fundsBreakdown(for order: HeldOrder) -> OrderFundsBreakdown {
        let total = max(0, order.amountMinor)

        if order.resolutionStatus == .cancelled {
            return OrderFundsBreakdown(
                totalMinor: total, pendingMinor: 0, deliveredMinor: 0,
                refundedMinor: 0, refundPendingMinor: 0, cancelledMinor: total,
                usesDeliveryFallback: false
            )
        }
        if order.resolutionStatus == .refunded {
            return OrderFundsBreakdown(
                totalMinor: total, pendingMinor: 0, deliveredMinor: 0,
                refundedMinor: total, refundPendingMinor: 0, cancelledMinor: 0,
                usesDeliveryFallback: false
            )
        }

        let refunded = min(total, explicitItemMinor(order: order, status: .refunded))
        let cancelled = min(total - refunded, explicitItemMinor(order: order, status: .cancelled))
        let hasRecordedDelivery = order.fulfillmentStatus == .delivered
            || order.fulfillmentStatus == .partiallyShipped
            || order.items.contains {
                $0.status == .delivered || $0.status == .shipped || $0.deliveredQuantity > 0
            }

        var delivered: Int64 = 0
        var usesDeliveryFallback = false
        if order.fulfillmentStatus == .delivered && order.items.isEmpty {
            delivered = max(0, total - refunded - cancelled)
        } else if hasRecordedDelivery {
            if let exact = exactDeliveredMinor(order: order) {
                delivered = min(exact, max(0, total - refunded - cancelled))
            } else {
                // Unknown allocations stay pending instead of inventing a refund
                // amount or treating the whole order as delivered.
                usesDeliveryFallback = true
            }
        }

        let accounted = min(total, delivered + refunded + cancelled)
        let pending = total - accounted
        let refundPending: Int64
        switch order.resolutionStatus {
        case .refundRequested, .disputed:
            refundPending = max(0, total - refunded - cancelled)
        case .none, .cancelled, .refunded:
            refundPending = 0
        }

        return OrderFundsBreakdown(
            totalMinor: total,
            pendingMinor: pending,
            deliveredMinor: delivered,
            refundedMinor: refunded,
            refundPendingMinor: refundPending,
            cancelledMinor: cancelled,
            usesDeliveryFallback: usesDeliveryFallback
        )
    }

    private static func explicitItemMinor(order: HeldOrder, status: ItemStatus) -> Int64 {
        order.items.reduce(0) { result, item in
            guard item.status == status, let amount = item.amountMinor, amount > 0 else {
                return result
            }
            return result + amount
        }
    }

    private static func exactDeliveredMinor(order: HeldOrder) -> Int64? {
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
            guard item.status != .cancelled && item.status != .refunded else { continue }
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
