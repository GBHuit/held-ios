import Foundation
import SwiftData

enum SeedData {
    static func installIfNeeded(context: ModelContext) throws {
        let orderCount = try context.fetchCount(FetchDescriptor<HeldOrder>())
        if orderCount == 0 {
            for order in makeOrders() {
                context.insert(order)
            }
        }

        _ = try AppSettings.fetchOrCreate(context: context)
        try context.save()
    }

    private static func makeOrders() -> [HeldOrder] {
        [
            makeAluminumOrder(),
            makeBotanicalOrder(),
            makeQK75NOrder(),
            makeCycle7Order(),
            makeLuminkeyOrder(),
            makeKBD67Order()
        ]
    }

    private static func date(_ value: String) -> Date {
        guard let date = iso8601Date(from: value) else {
            preconditionFailure("Invalid seed ISO8601 date: \(value)")
        }
        return date
    }

    private static func item(
        id: String,
        name: String,
        variant: String,
        quantity: Int,
        deliveredQuantity: Int,
        status: ItemStatus,
        amountMinor: Int64,
        order: HeldOrder
    ) -> OrderItem {
        OrderItem(
            id: id,
            name: name,
            variant: variant,
            quantity: quantity,
            deliveredQuantity: deliveredQuantity,
            status: status,
            amountMinor: amountMinor,
            order: order
        )
    }

    private static func milestone(
        id: String,
        kind: MilestoneKind,
        occurredAt: String,
        title: String,
        note: String,
        sourceURL: String? = nil,
        order: HeldOrder
    ) -> Milestone {
        Milestone(
            id: id,
            kind: kind,
            occurredAt: date(occurredAt),
            title: title,
            note: note,
            sourceURL: sourceURL,
            order: order
        )
    }

    private static func evidence(
        id: String,
        kind: EvidenceKind,
        title: String,
        filename: String,
        capturedAt: String,
        source: String,
        note: String,
        colorHex: String,
        order: HeldOrder
    ) -> Evidence {
        Evidence(
            id: id,
            kind: kind,
            title: title,
            filename: filename,
            capturedAt: date(capturedAt),
            source: source,
            note: note,
            colorHex: colorHex,
            order: order
        )
    }

    private static func reminder(
        id: String,
        kind: ReminderKind,
        triggerAt: String,
        leadDays: Int,
        enabled: Bool,
        label: String,
        order: HeldOrder
    ) -> HeldReminder {
        HeldReminder(
            id: id,
            kind: kind,
            triggerAt: date(triggerAt),
            leadDays: leadDays,
            enabled: enabled,
            label: label,
            order: order
        )
    }

    private static func makeAluminumOrder() -> HeldOrder {
        let orderedAt = date("2026-09-28T14:32:00Z")
        let order = HeldOrder(
            id: "order-aluminum-65",
            title: "Aluminum 65 — Midnight Navy",
            vendor: "Northline Keyboards",
            orderNumber: "NL-10482",
            orderedAt: orderedAt,
            amountMinor: 36800,
            currencyCode: .USD,
            paymentMethod: "Visa •••• 2048",
            sourceURL: "https://example.com/northline/aluminum-65",
            estimateText: "Complete order promised within 8–10 weeks, by November 12, 2026.",
            fulfillmentStatus: .partiallyShipped,
            resolutionStatus: .none,
            estimateEnd: date("2026-11-12T23:59:59Z"),
            nextCheckAt: date("2026-11-14T09:00:00Z"),
            lastUserUpdateAt: date("2026-10-20T11:15:00Z"),
            notes: "Do not mark complete until the PCB, plate, screws, and foam are all accounted for.",
            createdAt: orderedAt
        )

        order.items = [
            item(
                id: "item-aluminum-case",
                name: "Aluminum 65 case kit",
                variant: "Midnight Navy / brass weight",
                quantity: 1,
                deliveredQuantity: 1,
                status: .delivered,
                amountMinor: 26800,
                order: order
            ),
            item(
                id: "item-aluminum-pcb",
                name: "Hot-swap PCB and plate kit",
                variant: "ANSI / FR4 plate",
                quantity: 1,
                deliveredQuantity: 0,
                status: .pending,
                amountMinor: 10000,
                order: order
            )
        ]

        order.milestones = [
            milestone(
                id: "mile-aluminum-purchase",
                kind: .purchase,
                occurredAt: "2026-09-28T14:32:00Z",
                title: "Group-buy order confirmed",
                note: "Paid in full; the listing promised a complete delivery within 8–10 weeks.",
                sourceURL: "https://example.com/northline/aluminum-65",
                order: order
            ),
            milestone(
                id: "mile-aluminum-update",
                kind: .update,
                occurredAt: "2026-10-12T16:20:00Z",
                title: "CNC production completed",
                note: "Vendor shared finishing photos and said packing would begin the following week.",
                order: order
            ),
            milestone(
                id: "mile-aluminum-shipment",
                kind: .shipment,
                occurredAt: "2026-11-03T10:05:00Z",
                title: "Case kit shipped separately",
                note: "Tracking was issued for the case only; the PCB and plate were not included.",
                order: order
            ),
            milestone(
                id: "mile-aluminum-delivery",
                kind: .delivery,
                occurredAt: "2026-11-09T13:48:00Z",
                title: "Case kit delivered",
                note: "Outer case and brass weight arrived in good condition. One package remains open.",
                order: order
            ),
            milestone(
                id: "mile-aluminum-delay",
                kind: .delay,
                occurredAt: "2026-11-13T08:40:00Z",
                title: "Remaining parts moved to a later batch",
                note: "A vendor reply cited missing plates but did not provide a revised delivery date.",
                order: order
            )
        ]

        order.evidence = [
            evidence(
                id: "evidence-aluminum-receipt",
                kind: .receipt,
                title: "Payment receipt",
                filename: "northline-NL-10482-receipt.pdf",
                capturedAt: "2026-09-28T14:34:00Z",
                source: "Northline order email",
                note: "USD 368.00 charged in full for the complete keyboard kit.",
                colorHex: "#C97B5A",
                order: order
            ),
            evidence(
                id: "evidence-aluminum-listing",
                kind: .originalListing,
                title: "Original group-buy promise",
                filename: "aluminum-65-listing-2026-09-28.png",
                capturedAt: "2026-09-28T14:36:00Z",
                source: "Archived product page",
                note: "Captured text: ‘Complete orders ship within 8–10 weeks.’ No split shipment was stated.",
                colorHex: "#657C72",
                order: order
            ),
            evidence(
                id: "evidence-aluminum-shipping",
                kind: .shipping,
                title: "Split-shipment tracking",
                filename: "NL-10482-partial-tracking.pdf",
                capturedAt: "2026-11-03T10:08:00Z",
                source: "Carrier tracking page",
                note: "One parcel, 2.8 kg; contents description lists the aluminum case only.",
                colorHex: "#6C82A8",
                order: order
            ),
            evidence(
                id: "evidence-aluminum-communication",
                kind: .communication,
                title: "Vendor reply about remaining kit",
                filename: "northline-reply-2026-11-13.eml",
                capturedAt: "2026-11-13T09:02:00Z",
                source: "Support email",
                note: "No revised ship date was supplied for the outstanding PCB and plate kit.",
                colorHex: "#B28A54",
                order: order
            )
        ]

        order.reminders = [
            reminder(
                id: "reminder-aluminum-check",
                kind: .checkIn,
                triggerAt: "2026-11-14T09:00:00Z",
                leadDays: 0,
                enabled: true,
                label: "Request a firm date for the remaining kit",
                order: order
            ),
            reminder(
                id: "reminder-aluminum-deadline",
                kind: .deadline,
                triggerAt: "2026-11-22T18:00:00Z",
                leadDays: 7,
                enabled: true,
                label: "Escalate to tracking or a partial refund",
                order: order
            )
        ]

        return order
    }

    private static func makeBotanicalOrder() -> HeldOrder {
        let orderedAt = date("2026-07-18T09:14:00Z")
        let order = HeldOrder(
            id: "order-gmk-botanical",
            title: "GMK Botanical 2 — Base + Novelties",
            vendor: "Keyset Atelier",
            orderNumber: "KA-22190",
            orderedAt: orderedAt,
            amountMinor: 21400,
            currencyCode: .USD,
            paymentMethod: "Mastercard •••• 7712",
            sourceURL: "https://example.com/keyset-atelier/botanical-2",
            estimateText: "Original listing estimated delivery between October 30 and November 8, 2026.",
            fulfillmentStatus: .inProduction,
            resolutionStatus: .none,
            estimateEnd: date("2026-11-08T23:59:59Z"),
            nextCheckAt: date("2026-11-13T09:00:00Z"),
            lastUserUpdateAt: date("2026-10-15T17:30:00Z"),
            notes: "Keep the original listing: the current product page now shows a broader winter window.",
            createdAt: orderedAt
        )

        order.items = [
            item(
                id: "item-botanical-base",
                name: "Botanical 2 base kit",
                variant: "Double-shot ABS / US ANSI",
                quantity: 1,
                deliveredQuantity: 0,
                status: .pending,
                amountMinor: 15500,
                order: order
            ),
            item(
                id: "item-botanical-novelties",
                name: "Botanical 2 novelties",
                variant: "Leaf and accent kit",
                quantity: 1,
                deliveredQuantity: 0,
                status: .pending,
                amountMinor: 5900,
                order: order
            )
        ]

        order.milestones = [
            milestone(
                id: "mile-botanical-purchase",
                kind: .purchase,
                occurredAt: "2026-07-18T09:14:00Z",
                title: "Keyset preorder placed",
                note: "Original delivery window saved at checkout: October 30–November 8, 2026.",
                order: order
            ),
            milestone(
                id: "mile-botanical-update",
                kind: .update,
                occurredAt: "2026-09-02T12:10:00Z",
                title: "Color samples approved",
                note: "Vendor announced final color approval and said production had entered the queue.",
                order: order
            ),
            milestone(
                id: "mile-botanical-delay",
                kind: .delay,
                occurredAt: "2026-10-29T15:45:00Z",
                title: "Original delivery window slipped",
                note: "A short update mentioned factory congestion without giving a replacement window.",
                order: order
            ),
            milestone(
                id: "mile-botanical-followup",
                kind: .update,
                occurredAt: "2026-11-10T10:25:00Z",
                title: "No revised date after follow-up",
                note: "Support acknowledged the delay and repeated that the set was still in production.",
                order: order
            )
        ]

        order.evidence = [
            evidence(
                id: "evidence-botanical-receipt",
                kind: .receipt,
                title: "Preorder invoice",
                filename: "KA-22190-invoice.pdf",
                capturedAt: "2026-07-18T09:16:00Z",
                source: "Keyset Atelier account",
                note: "Base kit and novelties paid together; USD 214.00 total.",
                colorHex: "#C97B5A",
                order: order
            ),
            evidence(
                id: "evidence-botanical-listing",
                kind: .originalListing,
                title: "Original delivery estimate",
                filename: "botanical-2-original-listing.png",
                capturedAt: "2026-07-18T09:18:00Z",
                source: "Archived product page",
                note: "Shows the October 30–November 8 estimate before the page was edited.",
                colorHex: "#657C72",
                order: order
            ),
            evidence(
                id: "evidence-botanical-terms",
                kind: .terms,
                title: "Preorder cancellation terms",
                filename: "keyset-atelier-preorder-terms.pdf",
                capturedAt: "2026-07-18T09:20:00Z",
                source: "Vendor terms page",
                note: "Refund requests require a support ticket before the order enters final packing.",
                colorHex: "#8B7398",
                order: order
            ),
            evidence(
                id: "evidence-botanical-communication",
                kind: .communication,
                title: "Delay acknowledgement",
                filename: "KA-22190-support-2026-11-10.eml",
                capturedAt: "2026-11-10T10:28:00Z",
                source: "Support email",
                note: "Vendor confirmed the original window was missed but offered no revised estimate.",
                colorHex: "#B28A54",
                order: order
            )
        ]

        order.reminders = [
            reminder(
                id: "reminder-botanical-check",
                kind: .checkIn,
                triggerAt: "2026-11-13T09:00:00Z",
                leadDays: 0,
                enabled: true,
                label: "Ask for a written replacement estimate",
                order: order
            ),
            reminder(
                id: "reminder-botanical-deadline",
                kind: .deadline,
                triggerAt: "2026-11-28T18:00:00Z",
                leadDays: 14,
                enabled: true,
                label: "Decide whether to request a preorder refund",
                order: order
            )
        ]

        return order
    }


    private static func makeQK75NOrder() -> HeldOrder {
        let orderedAt = date("2026-08-04T11:05:00Z")
        let order = HeldOrder(
            id: "order-qk75n",
            title: "QK75N — Silver / PVD Weight",
            vendor: "Qwertykeys",
            orderNumber: "QK-58316",
            orderedAt: orderedAt,
            amountMinor: 18900,
            currencyCode: .USD,
            paymentMethod: "PayPal",
            sourceURL: "https://example.com/qwertykeys/qk75n",
            estimateText: "In-stock order promised for delivery by October 20, 2026.",
            fulfillmentStatus: .delivered,
            resolutionStatus: .none,
            estimateEnd: date("2026-10-20T23:59:59Z"),
            lastUserUpdateAt: date("2026-10-22T18:12:00Z"),
            notes: "Complete. Delivered against the original promise with no missing components.",
            createdAt: orderedAt
        )

        order.items = [
            item(
                id: "item-qk75n-kit",
                name: "QK75N keyboard kit",
                variant: "Anodized silver / mirrored PVD",
                quantity: 1,
                deliveredQuantity: 1,
                status: .delivered,
                amountMinor: 16900,
                order: order
            ),
            item(
                id: "item-qk75n-stabilizers",
                name: "Screw-in stabilizer set",
                variant: "Clear housing / 1.6 mm",
                quantity: 1,
                deliveredQuantity: 1,
                status: .delivered,
                amountMinor: 2000,
                order: order
            )
        ]

        order.milestones = [
            milestone(
                id: "mile-qk75n-purchase",
                kind: .purchase,
                occurredAt: "2026-08-04T11:05:00Z",
                title: "In-stock order placed",
                note: "Keyboard and stabilizers purchased together with a single delivery estimate.",
                order: order
            ),
            milestone(
                id: "mile-qk75n-update",
                kind: .update,
                occurredAt: "2026-09-26T09:30:00Z",
                title: "Packing confirmation",
                note: "Vendor confirmed both line items were reserved in the same parcel.",
                order: order
            ),
            milestone(
                id: "mile-qk75n-shipment",
                kind: .shipment,
                occurredAt: "2026-10-15T07:52:00Z",
                title: "Parcel collected by carrier",
                note: "Tracking showed one package containing both ordered items.",
                order: order
            ),
            milestone(
                id: "mile-qk75n-delivery",
                kind: .delivery,
                occurredAt: "2026-10-19T14:18:00Z",
                title: "Delivered one day early",
                note: "Package opened and checked; all components matched the invoice.",
                order: order
            )
        ]

        order.evidence = [
            evidence(
                id: "evidence-qk75n-receipt",
                kind: .receipt,
                title: "Paid invoice",
                filename: "QK-58316-invoice.pdf",
                capturedAt: "2026-08-04T11:07:00Z",
                source: "Qwertykeys account",
                note: "USD 189.00 paid via PayPal.",
                colorHex: "#C97B5A",
                order: order
            ),
            evidence(
                id: "evidence-qk75n-listing",
                kind: .originalListing,
                title: "In-stock listing archive",
                filename: "qk75n-listing.png",
                capturedAt: "2026-08-04T11:09:00Z",
                source: "Archived product page",
                note: "Original delivery promise and kit contents preserved for comparison.",
                colorHex: "#657C72",
                order: order
            ),
            evidence(
                id: "evidence-qk75n-shipping",
                kind: .shipping,
                title: "Proof of delivery",
                filename: "QK-58316-delivery.pdf",
                capturedAt: "2026-10-19T14:20:00Z",
                source: "Carrier tracking page",
                note: "Signed delivery scan recorded October 19 at 14:18.",
                colorHex: "#6C82A8",
                order: order
            )
        ]

        order.reminders = [
            reminder(
                id: "reminder-qk75n-check",
                kind: .checkIn,
                triggerAt: "2026-10-25T09:00:00Z",
                leadDays: 0,
                enabled: false,
                label: "Inspect the board after first build",
                order: order
            ),
            reminder(
                id: "reminder-qk75n-deadline",
                kind: .deadline,
                triggerAt: "2026-11-02T18:00:00Z",
                leadDays: 7,
                enabled: false,
                label: "Return window closed",
                order: order
            )
        ]

        return order
    }

    private static func makeCycle7Order() -> HeldOrder {
        let orderedAt = date("2026-10-02T16:42:00Z")
        let order = HeldOrder(
            id: "order-cycle7-uk",
            title: "Cycle7 — British Racing Green",
            vendor: "Prototypist UK",
            orderNumber: "PT-78421",
            orderedAt: orderedAt,
            amountMinor: 27900,
            currencyCode: .GBP,
            paymentMethod: "Visa •••• 1094",
            sourceURL: "https://example.com/prototypist/cycle7",
            estimateText: "Tracked UK delivery promised for November 16–18, 2026.",
            fulfillmentStatus: .shipped,
            resolutionStatus: .none,
            estimateEnd: date("2026-11-18T23:59:59Z"),
            nextCheckAt: date("2026-11-16T08:00:00Z"),
            lastUserUpdateAt: date("2026-11-12T19:05:00Z"),
            notes: "UK order; no customs payment is due. Retain tracking until both line items are checked.",
            createdAt: orderedAt
        )

        order.items = [
            item(
                id: "item-cycle7-kit",
                name: "Cycle7 keyboard kit",
                variant: "British Racing Green / WK",
                quantity: 1,
                deliveredQuantity: 0,
                status: .shipped,
                amountMinor: 25900,
                order: order
            ),
            item(
                id: "item-cycle7-badges",
                name: "Interchangeable badge set",
                variant: "Brass / black aluminum",
                quantity: 1,
                deliveredQuantity: 0,
                status: .shipped,
                amountMinor: 2000,
                order: order
            )
        ]

        order.milestones = [
            milestone(
                id: "mile-cycle7-purchase",
                kind: .purchase,
                occurredAt: "2026-10-02T16:42:00Z",
                title: "UK order confirmed",
                note: "Paid GBP 279.00 with tracked delivery estimated for November 16–18.",
                order: order
            ),
            milestone(
                id: "mile-cycle7-update",
                kind: .update,
                occurredAt: "2026-10-30T13:20:00Z",
                title: "Quality check completed",
                note: "Vendor confirmed the kit and badge set had passed final inspection.",
                order: order
            ),
            milestone(
                id: "mile-cycle7-shipment",
                kind: .shipment,
                occurredAt: "2026-11-12T18:55:00Z",
                title: "Tracked parcel dispatched",
                note: "Carrier accepted the parcel in Leeds; delivery remains inside the original window.",
                order: order
            )
        ]

        order.evidence = [
            evidence(
                id: "evidence-cycle7-receipt",
                kind: .receipt,
                title: "UK VAT receipt",
                filename: "PT-78421-receipt.pdf",
                capturedAt: "2026-10-02T16:44:00Z",
                source: "Prototypist order email",
                note: "GBP 279.00 including VAT and tracked shipping.",
                colorHex: "#C97B5A",
                order: order
            ),
            evidence(
                id: "evidence-cycle7-listing",
                kind: .originalListing,
                title: "Original UK delivery window",
                filename: "cycle7-delivery-promise.png",
                capturedAt: "2026-10-02T16:46:00Z",
                source: "Archived checkout page",
                note: "Checkout showed tracked delivery for November 16–18, 2026.",
                colorHex: "#657C72",
                order: order
            ),
            evidence(
                id: "evidence-cycle7-shipping",
                kind: .shipping,
                title: "Royal Mail tracking snapshot",
                filename: "PT-78421-tracking.pdf",
                capturedAt: "2026-11-12T19:02:00Z",
                source: "Carrier tracking page",
                note: "Parcel acceptance scan and promised service level captured together.",
                colorHex: "#6C82A8",
                order: order
            )
        ]

        order.reminders = [
            reminder(
                id: "reminder-cycle7-check",
                kind: .checkIn,
                triggerAt: "2026-11-16T08:00:00Z",
                leadDays: 1,
                enabled: true,
                label: "Check for the first delivery scan",
                order: order
            ),
            reminder(
                id: "reminder-cycle7-deadline",
                kind: .deadline,
                triggerAt: "2026-11-22T18:00:00Z",
                leadDays: 7,
                enabled: true,
                label: "Open a trace if delivery has not occurred",
                order: order
            )
        ]

        return order
    }


    private static func makeLuminkeyOrder() -> HeldOrder {
        let orderedAt = date("2026-10-12T08:26:00Z")
        let order = HeldOrder(
            id: "order-luminkey-eu",
            title: "Luminkey65 — Champagne",
            vendor: "CandyKeys Europe",
            orderNumber: "CK-90634",
            orderedAt: orderedAt,
            amountMinor: 24900,
            currencyCode: .EUR,
            paymentMethod: "SEPA card •••• 4410",
            sourceURL: "https://example.com/candykeys/luminkey65",
            estimateText: "Dispatch from the EU warehouse promised by December 4, 2026.",
            fulfillmentStatus: .ordered,
            resolutionStatus: .none,
            estimateEnd: date("2026-12-04T23:59:59Z"),
            nextCheckAt: date("2026-11-20T09:00:00Z"),
            lastUserUpdateAt: date("2026-11-10T12:35:00Z"),
            notes: "European VAT-inclusive order. The current commitment is dispatch, not final delivery.",
            createdAt: orderedAt
        )

        order.items = [
            item(
                id: "item-luminkey-kit",
                name: "Luminkey65 keyboard kit",
                variant: "Champagne / ISO-DE hot-swap",
                quantity: 1,
                deliveredQuantity: 0,
                status: .pending,
                amountMinor: 22900,
                order: order
            ),
            item(
                id: "item-luminkey-case",
                name: "Travel sleeve",
                variant: "Sand canvas / 65 percent",
                quantity: 1,
                deliveredQuantity: 0,
                status: .pending,
                amountMinor: 2000,
                order: order
            )
        ]

        order.milestones = [
            milestone(
                id: "mile-luminkey-purchase",
                kind: .purchase,
                occurredAt: "2026-10-12T08:26:00Z",
                title: "EU preorder confirmed",
                note: "Paid EUR 249.00; dispatch was promised by December 4 from the EU warehouse.",
                order: order
            ),
            milestone(
                id: "mile-luminkey-update",
                kind: .update,
                occurredAt: "2026-11-02T09:50:00Z",
                title: "Inventory allocation received",
                note: "The ISO-DE kit and sleeve were both allocated to the order.",
                order: order
            ),
            milestone(
                id: "mile-luminkey-followup",
                kind: .update,
                occurredAt: "2026-11-10T12:30:00Z",
                title: "Warehouse schedule reconfirmed",
                note: "Support said the original dispatch commitment still stands.",
                order: order
            )
        ]

        order.evidence = [
            evidence(
                id: "evidence-luminkey-receipt",
                kind: .receipt,
                title: "EUR order invoice",
                filename: "CK-90634-invoice.pdf",
                capturedAt: "2026-10-12T08:28:00Z",
                source: "CandyKeys account",
                note: "EUR 249.00 paid, including EU VAT.",
                colorHex: "#C97B5A",
                order: order
            ),
            evidence(
                id: "evidence-luminkey-listing",
                kind: .originalListing,
                title: "Original dispatch commitment",
                filename: "luminkey65-eu-listing.png",
                capturedAt: "2026-10-12T08:30:00Z",
                source: "Archived product page",
                note: "Preserved statement: ‘EU orders dispatch no later than December 4.’",
                colorHex: "#657C72",
                order: order
            ),
            evidence(
                id: "evidence-luminkey-terms",
                kind: .terms,
                title: "EU cancellation rights",
                filename: "candykeys-eu-terms.pdf",
                capturedAt: "2026-10-12T08:32:00Z",
                source: "Vendor terms page",
                note: "Cancellation and withdrawal clauses saved with the original purchase terms.",
                colorHex: "#8B7398",
                order: order
            ),
            evidence(
                id: "evidence-luminkey-communication",
                kind: .communication,
                title: "Schedule confirmation",
                filename: "CK-90634-support-2026-11-10.eml",
                capturedAt: "2026-11-10T12:35:00Z",
                source: "Support email",
                note: "Vendor explicitly reconfirmed the December 4 dispatch commitment.",
                colorHex: "#B28A54",
                order: order
            )
        ]

        order.reminders = [
            reminder(
                id: "reminder-luminkey-check",
                kind: .checkIn,
                triggerAt: "2026-11-20T09:00:00Z",
                leadDays: 0,
                enabled: true,
                label: "Verify that the warehouse schedule is unchanged",
                order: order
            ),
            reminder(
                id: "reminder-luminkey-deadline",
                kind: .deadline,
                triggerAt: "2026-12-11T18:00:00Z",
                leadDays: 7,
                enabled: true,
                label: "Follow up if dispatch is one week late",
                order: order
            )
        ]

        return order
    }

    private static func makeKBD67Order() -> HeldOrder {
        let orderedAt = date("2026-09-10T10:18:00Z")
        let order = HeldOrder(
            id: "order-kbd67-refund",
            title: "KBD67 Lite R5 — Lavender",
            vendor: "KBDfans",
            orderNumber: "KB-34771",
            orderedAt: orderedAt,
            amountMinor: 13900,
            currencyCode: .USD,
            paymentMethod: "PayPal",
            sourceURL: "https://example.com/kbdfans/kbd67-lite-r5",
            estimateText: "Delivery promised by October 28, 2026; return postage promised after approval.",
            fulfillmentStatus: .delivered,
            resolutionStatus: .refundRequested,
            estimateEnd: date("2026-10-28T23:59:59Z"),
            nextCheckAt: date("2026-11-17T09:00:00Z"),
            lastUserUpdateAt: date("2026-11-14T15:45:00Z"),
            notes: "The physical order is delivered; it remains active only because the refund is unresolved.",
            createdAt: orderedAt
        )

        order.items = [
            item(
                id: "item-kbd67-kit",
                name: "KBD67 Lite keyboard kit",
                variant: "Lavender / ANSI",
                quantity: 1,
                deliveredQuantity: 1,
                status: .delivered,
                amountMinor: 11900,
                order: order
            ),
            item(
                id: "item-kbd67-cable",
                name: "Coiled USB-C cable",
                variant: "Lavender / aviator connector",
                quantity: 1,
                deliveredQuantity: 1,
                status: .delivered,
                amountMinor: 2000,
                order: order
            )
        ]

        order.milestones = [
            milestone(
                id: "mile-kbd67-purchase",
                kind: .purchase,
                occurredAt: "2026-09-10T10:18:00Z",
                title: "Order placed",
                note: "Keyboard and matching cable ordered with delivery promised by October 28.",
                order: order
            ),
            milestone(
                id: "mile-kbd67-shipment",
                kind: .shipment,
                occurredAt: "2026-10-22T06:45:00Z",
                title: "Parcel shipped",
                note: "Both items were included in a single tracked shipment.",
                order: order
            ),
            milestone(
                id: "mile-kbd67-delivery",
                kind: .delivery,
                occurredAt: "2026-10-26T12:14:00Z",
                title: "Delivered inside the promise",
                note: "Delivery was on time, but inspection revealed a persistent PCB fault.",
                order: order
            ),
            milestone(
                id: "mile-kbd67-refund",
                kind: .refund,
                occurredAt: "2026-11-09T09:35:00Z",
                title: "Refund requested",
                note: "Requested a full refund and prepaid return label with diagnostic photos attached.",
                order: order
            ),
            milestone(
                id: "mile-kbd67-update",
                kind: .update,
                occurredAt: "2026-11-14T15:45:00Z",
                title: "Return postage still unresolved",
                note: "Vendor acknowledged the fault but has not yet supplied the promised return label.",
                order: order
            )
        ]

        order.evidence = [
            evidence(
                id: "evidence-kbd67-receipt",
                kind: .receipt,
                title: "PayPal payment record",
                filename: "KB-34771-payment.pdf",
                capturedAt: "2026-09-10T10:20:00Z",
                source: "PayPal activity",
                note: "USD 139.00 paid for the keyboard and cable.",
                colorHex: "#C97B5A",
                order: order
            ),
            evidence(
                id: "evidence-kbd67-shipping",
                kind: .shipping,
                title: "Delivery record",
                filename: "KB-34771-delivery.pdf",
                capturedAt: "2026-10-26T12:20:00Z",
                source: "Carrier tracking page",
                note: "Proof of delivery establishes the start of the return window.",
                colorHex: "#6C82A8",
                order: order
            ),
            evidence(
                id: "evidence-kbd67-terms",
                kind: .terms,
                title: "Faulty-item return terms",
                filename: "kbdfans-return-terms.pdf",
                capturedAt: "2026-11-09T09:32:00Z",
                source: "Vendor returns page",
                note: "Terms state that confirmed faulty items qualify for prepaid return postage.",
                colorHex: "#8B7398",
                order: order
            ),
            evidence(
                id: "evidence-kbd67-communication",
                kind: .communication,
                title: "Fault acknowledgement and refund request",
                filename: "KB-34771-support-thread.eml",
                capturedAt: "2026-11-14T15:48:00Z",
                source: "Support email",
                note: "Includes the original refund request, fault acknowledgement, and missing-label follow-up.",
                colorHex: "#B28A54",
                order: order
            )
        ]

        order.reminders = [
            reminder(
                id: "reminder-kbd67-check",
                kind: .checkIn,
                triggerAt: "2026-11-17T09:00:00Z",
                leadDays: 1,
                enabled: true,
                label: "Check for the prepaid return label",
                order: order
            ),
            reminder(
                id: "reminder-kbd67-deadline",
                kind: .deadline,
                triggerAt: "2026-11-25T18:00:00Z",
                leadDays: 10,
                enabled: true,
                label: "Escalate through PayPal if postage is unresolved",
                order: order
            )
        ]

        return order
    }
}
