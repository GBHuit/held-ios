import SwiftUI

// MARK: - Header

struct OrderDetailHeader: View {
    @EnvironmentObject private var localization: LocalizationCenter
    let order: HeldOrder

    var body: some View {
        HeldCard {
            VStack(alignment: .leading, spacing: HeldSpacing.medium) {
                VStack(alignment: .leading, spacing: HeldSpacing.small) {
                    Text(order.title)
                        .heldDisplay(size: 34)
                        .foregroundStyle(HeldColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    Text(order.vendor.isEmpty ? L("Vendor not recorded") : order.vendor)
                        .font(.title3)
                        .foregroundStyle(HeldColor.secondaryInk)
                }

                Divider().overlay(HeldColor.separator)

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: HeldSpacing.large) {
                        orderNumber
                        amount
                    }
                    VStack(alignment: .leading, spacing: HeldSpacing.medium) {
                        orderNumber
                        amount
                    }
                }

                VStack(alignment: .leading, spacing: HeldSpacing.extraSmall) {
                    Label(L("Ordered %@", localization.date(order.orderedAt)), systemImage: "calendar")
                    if !order.paymentMethod.isEmpty {
                        Label(order.paymentMethod, systemImage: "creditcard")
                    }
                    if let sourceURL = URL(string: order.sourceURL), !order.sourceURL.isEmpty {
                        Link(destination: sourceURL) {
                            Label(L("Open original order source"), systemImage: "safari")
                        }
                    }
                }
                .heldCaption()
                .foregroundStyle(HeldColor.secondaryInk)
            }
        }
    }

    private var orderNumber: some View {
        OrderDetailMetadataRow(
            title: L("Order number"),
            value: order.orderNumber.isEmpty ? L("Not recorded") : order.orderNumber
        )
    }

    private var amount: some View {
        OrderDetailMetadataRow(
            title: L("Order amount"),
            value: localization.money(minor: order.amountMinor, currency: order.currencyCode)
        )
    }
}

// MARK: - Independent statuses and progress

struct OrderStatusSection: View {
    @EnvironmentObject private var localization: LocalizationCenter
    let order: HeldOrder
    let onFulfillmentChange: (FulfillmentStatus) -> Void
    let onResolutionChange: (ResolutionStatus) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HeldSpacing.medium) {
            HeldSectionHeader(
                title: L("Status"),
                subtitle: L("Physical delivery and refund or dispute resolution are tracked independently.")
            )

            HeldCard {
                VStack(alignment: .leading, spacing: HeldSpacing.large) {
                    VStack(alignment: .leading, spacing: HeldSpacing.small) {
                        HStack {
                            Text(L("Order progress"))
                                .font(.headline)
                            Spacer()
                            Text(localization.percentage(order.progress))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(HeldColor.secondaryInk)
                        }
                        HeldProgressView(value: order.progress)
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: HeldSpacing.medium) {
                            fulfillmentMenu
                            resolutionMenu
                        }
                        VStack(spacing: HeldSpacing.medium) {
                            fulfillmentMenu
                            resolutionMenu
                        }
                    }
                }
            }
        }
    }

    private var fulfillmentMenu: some View {
        Menu {
            Picker(L("Fulfillment status"), selection: fulfillmentBinding) {
                ForEach(FulfillmentStatus.allCases, id: \.self) { status in
                    Label(localizedFulfillmentStatusLabel(status), systemImage: status.symbolName).tag(status)
                }
            }
        } label: {
            StatusMenuLabel(
                title: L("Fulfillment"),
                value: localizedFulfillmentStatusLabel(order.fulfillmentStatus),
                symbolName: order.fulfillmentStatus.symbolName
            )
        }
        .accessibilityLabel(L("Fulfillment status: %@", localizedFulfillmentStatusLabel(order.fulfillmentStatus)))
        .accessibilityHint(L("Changes physical delivery status only"))
    }

    private var resolutionMenu: some View {
        Menu {
            Picker(L("Resolution status"), selection: resolutionBinding) {
                ForEach(ResolutionStatus.allCases, id: \.self) { status in
                    Label(localizedResolutionStatusLabel(status), systemImage: status.symbolName).tag(status)
                }
            }
        } label: {
            StatusMenuLabel(
                title: L("Resolution"),
                value: localizedResolutionStatusLabel(order.resolutionStatus),
                symbolName: order.resolutionStatus.symbolName
            )
        }
        .accessibilityLabel(L("Resolution status: %@", localizedResolutionStatusLabel(order.resolutionStatus)))
        .accessibilityHint(L("Changes cancellation, refund, or dispute status only"))
    }

    private var fulfillmentBinding: Binding<FulfillmentStatus> {
        Binding(
            get: { order.fulfillmentStatus },
            set: { newValue in
                guard newValue != order.fulfillmentStatus else { return }
                onFulfillmentChange(newValue)
            }
        )
    }

    private var resolutionBinding: Binding<ResolutionStatus> {
        Binding(
            get: { order.resolutionStatus },
            set: { newValue in
                guard newValue != order.resolutionStatus else { return }
                onResolutionChange(newValue)
            }
        )
    }
}

private struct StatusMenuLabel: View {
    @EnvironmentObject private var localization: LocalizationCenter
    let title: String
    let value: String
    let symbolName: String

    var body: some View {
        HStack(spacing: HeldSpacing.medium) {
            Image(systemName: symbolName)
                .font(.title3)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .heldCaption()
                Text(value)
                    .font(.headline)
                    .lineLimit(2)
            }
            Spacer(minLength: HeldSpacing.small)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption)
        }
        .foregroundStyle(HeldColor.accent)
        .padding(HeldSpacing.medium)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(HeldColor.accentSoft.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Estimate and follow-up

struct OrderEstimateSection: View {
    @EnvironmentObject private var localization: LocalizationCenter
    let order: HeldOrder

    var body: some View {
        VStack(alignment: .leading, spacing: HeldSpacing.medium) {
            HeldSectionHeader(title: L("Promise & follow-up"))

            VStack(spacing: HeldSpacing.medium) {
                OrderDetailCallout(
                    title: L("Original estimate · locked"),
                    message: order.estimateText.isEmpty
                        ? L("No original estimate text was recorded. Revisions are added as milestones without replacing this field.")
                        : order.estimateText,
                    symbolName: "lock.fill",
                    tone: .warning
                )

                HeldCard {
                    VStack(alignment: .leading, spacing: HeldSpacing.medium) {
                        OrderDetailMetadataRow(
                            title: L("Current estimate · %@", localizedEstimatePrecisionLabel(order.estimatePrecision)),
                            value: localizedEstimateText(precision: order.estimatePrecision, start: order.estimateStart, end: order.estimateEnd)
                        )
                        if let range = localizedEstimateRangeText(start: order.estimateStart, end: order.estimateEnd) {
                            OrderDetailMetadataRow(
                                title: L("Stored range boundaries"),
                                value: range
                            )
                        }
                        OrderDetailMetadataRow(
                            title: L("Next check"),
                            value: order.nextCheckAt.map(orderDetailDateTime) ?? L("Not scheduled")
                        )
                        OrderDetailMetadataRow(
                            title: L("Last user update"),
                            value: orderDetailDateTime(order.lastUserUpdateAt)
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Line items

struct OrderItemsSection: View {
    @EnvironmentObject private var localization: LocalizationCenter
    let order: HeldOrder
    let onUpdate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HeldSpacing.medium) {
            HeldSectionHeader(
                title: L("Items"),
                subtitle: L("Record partial arrivals without completing the whole order.")
            ) {
                Button(L("Update delivery"), action: onUpdate)
                    .heldButtonStyle(.secondary)
            }

            if order.items.isEmpty {
                HeldCard {
                    Text(L("No line items are recorded for this order."))
                        .foregroundStyle(HeldColor.secondaryInk)
                }
            } else {
                VStack(spacing: HeldSpacing.small) {
                    ForEach(order.items, id: \.id) { item in
                        OrderItemRow(item: item)
                    }
                }
            }
        }
    }
}

private struct OrderItemRow: View {
    @EnvironmentObject private var localization: LocalizationCenter
    let item: OrderItem

    var body: some View {
        HeldCard(padding: HeldSpacing.medium) {
            VStack(alignment: .leading, spacing: HeldSpacing.small) {
                HStack(alignment: .top, spacing: HeldSpacing.medium) {
                    VStack(alignment: .leading, spacing: HeldSpacing.extraSmall) {
                        Text(item.name)
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        if !item.variant.isEmpty {
                            Text(item.variant)
                                .heldCaption()
                                .foregroundStyle(HeldColor.secondaryInk)
                        }
                    }
                    Spacer(minLength: HeldSpacing.small)
                    HeldBadge(text: localizedItemStatusLabel(item.status), tone: item.status.badgeTone)
                }

                HStack {
                    Label(
                        L("%1$lld of %2$lld delivered", min(item.deliveredQuantity, item.quantity), item.quantity),
                        systemImage: "shippingbox"
                    )
                    Spacer()
                    if let amountMinor = item.amountMinor {
                        Text(localization.money(minor: amountMinor, currency: item.order?.currencyCode ?? .USD))
                    }
                }
                .heldCaption()
                .foregroundStyle(HeldColor.secondaryInk)

                if item.quantity > 0 {
                    HeldProgressView(value: Double(min(item.deliveredQuantity, item.quantity)) / Double(item.quantity))
                }
            }
            .accessibilityElement(children: .contain)
        }
    }
}

extension ItemStatus {
    var badgeTone: BadgeTone {
        switch self {
        case .pending: return .neutral
        case .shipped: return .info
        case .delivered: return .success
        case .cancelled, .refunded: return .danger
        }
    }
}

// MARK: - Timeline

struct OrderTimelineSection: View {
    @EnvironmentObject private var localization: LocalizationCenter
    let order: HeldOrder
    let onAdd: () -> Void

    private var milestones: [Milestone] {
        order.milestones.sorted {
            if $0.occurredAt == $1.occurredAt { return $0.id < $1.id }
            return $0.occurredAt < $1.occurredAt
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HeldSpacing.medium) {
            HeldSectionHeader(
                title: L("Timeline"),
                subtitle: L("A chronological record of the promise and what changed.")
            ) {
                Button(action: onAdd) {
                    Label(L("Add milestone"), systemImage: "plus")
                }
                .heldButtonStyle(.secondary)
            }

            if milestones.isEmpty {
                HeldCard {
                    Text(L("No milestones yet. Add the first vendor update, shipment, delivery, or resolution event."))
                        .foregroundStyle(HeldColor.secondaryInk)
                }
            } else {
                HeldCard {
                    VStack(spacing: 0) {
                        ForEach(Array(milestones.enumerated()), id: \.element.id) { index, milestone in
                            MilestoneRow(milestone: milestone, isLast: index == milestones.count - 1)
                        }
                    }
                }
            }
        }
    }
}

private struct MilestoneRow: View {
    @EnvironmentObject private var localization: LocalizationCenter
    let milestone: Milestone
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: HeldSpacing.medium) {
            VStack(spacing: 0) {
                Image(systemName: milestone.kind.symbolName)
                    .font(.callout)
                    .foregroundStyle(HeldColor.accent)
                    .frame(width: 32, height: 32)
                    .background(HeldColor.accentSoft, in: Circle())
                if !isLast {
                    Rectangle()
                        .fill(HeldColor.separator)
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: HeldSpacing.extraSmall) {
                Text(milestone.title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L("%1$@ · %2$@", localizedMilestoneKindLabel(milestone.kind), orderDetailDateTime(milestone.occurredAt)))
                    .heldCaption()
                    .foregroundStyle(HeldColor.secondaryInk)
                if !milestone.note.isEmpty {
                    Text(milestone.note)
                        .heldBody()
                        .foregroundStyle(HeldColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let source = milestone.sourceURL,
                   let url = URL(string: source), !source.isEmpty {
                    Link(L("View milestone source"), destination: url)
                        .heldCaption()
                }
            }
            .padding(.bottom, isLast ? 0 : HeldSpacing.large)
        }
    }
}

// MARK: - Notes and tracking

struct OrderNotesSection: View {
    @EnvironmentObject private var localization: LocalizationCenter
    let order: HeldOrder
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HeldSpacing.medium) {
            HeldSectionHeader(title: L("Notes & tracking")) {
                Button(L("Edit"), action: onEdit)
                    .heldButtonStyle(.quiet)
            }

            HeldCard {
                VStack(alignment: .leading, spacing: HeldSpacing.medium) {
                    VStack(alignment: .leading, spacing: HeldSpacing.extraSmall) {
                        Text(L("Notes"))
                            .heldCaption()
                            .foregroundStyle(HeldColor.secondaryInk)
                        Text(order.notes.isEmpty ? L("No notes recorded.") : order.notes)
                            .heldBody()
                            .foregroundStyle(order.notes.isEmpty ? HeldColor.secondaryInk : HeldColor.ink)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Divider().overlay(HeldColor.separator)
                    OrderDetailMetadataRow(
                        title: L("Carrier"),
                        value: order.carrier.isEmpty ? L("Not recorded") : order.carrier
                    )
                    OrderDetailMetadataRow(
                        title: L("Tracking number"),
                        value: order.trackingNumber.isEmpty ? L("Not recorded") : order.trackingNumber,
                        monospaced: !order.trackingNumber.isEmpty
                    )
                }
            }
        }
    }
}

// MARK: - Destructive action

struct OrderDangerSection: View {
    @EnvironmentObject private var localization: LocalizationCenter
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HeldSpacing.medium) {
            Divider().overlay(HeldColor.separator)
            Button(role: .destructive, action: onDelete) {
                Label(L("Delete order"), systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .heldButtonStyle(.quiet)
            .foregroundStyle(HeldColor.danger)
            .accessibilityHint(L("Deletes this order, its reminders, evidence metadata, and imported attachments after confirmation"))
        }
    }
}
