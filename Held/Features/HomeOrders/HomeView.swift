import SwiftUI
import SwiftData

struct HomeView: View {
    @Query private var orders: [HeldOrder]
    @Query private var settings: [AppSettings]
    @Environment(\.modelContext) private var modelContext

    @State private var showingAddOrder = false

    private var currentSettings: AppSettings {
        settings.first ?? AppSettings()
    }

    private var activeOrders: [HeldOrder] {
        orders.filter(\.isActive)
    }

    private var attentionItems: [OrderAttention] {
        AttentionEngine.attention(orders: orders, settings: currentSettings).sorted { lhs, rhs in
            let leftRank = lhs.reasons.map { attentionRank($0.kind) }.min() ?? Int.max
            let rightRank = rhs.reasons.map { attentionRank($0.kind) }.min() ?? Int.max
            if leftRank != rightRank { return leftRank < rightRank }
            return lhs.order.orderedAt > rhs.order.orderedAt
        }
    }

    private var recentOrders: [HeldOrder] {
        orders.sorted { $0.orderedAt > $1.orderedAt }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Good morning."
        case 12..<18: return "Good afternoon."
        default: return "Good evening."
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if orders.isEmpty {
                    VStack(spacing: HeldSpacing.large) {
                        header
                        HeldEmptyView(
                            icon: "shippingbox",
                            title: "Give every promise a place",
                            message: "Add an order to keep its original estimate, progress, evidence, and next check-in together.",
                            buttonTitle: "Add your first order",
                            action: { showingAddOrder = true }
                        )
                        .frame(minHeight: 360)
                    }
                    .padding(.horizontal, HeldSpacing.medium)
                } else {
                    LazyVStack(alignment: .leading, spacing: HeldSpacing.extraLarge) {
                        header
                        addOrderButton
                        summary
                        attentionSection
                        recentSection
                    }
                    .padding(.horizontal, HeldSpacing.medium)
                    .padding(.vertical, HeldSpacing.large)
                }
            }
            .heldScreenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddOrder = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add a new order")
                }
            }
            .sheet(isPresented: $showingAddOrder) {
                AddOrderView()
            }
            .task {
                ensureSettingsExist()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: HeldSpacing.small) {
            Text("Held")
                .heldDisplay(size: 36)
                .foregroundStyle(HeldColor.accent)
                .accessibilityAddTraits(.isHeader)

            Text(greeting)
                .heldDisplay(size: 30)
                .foregroundStyle(HeldColor.ink)

            Text("Keep the original promise in view, and the next step close.")
                .heldBody()
                .foregroundStyle(HeldColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, HeldSpacing.small)
    }

    private var addOrderButton: some View {
        Button {
            showingAddOrder = true
        } label: {
            Label("Add a new order", systemImage: "plus")
                .frame(maxWidth: .infinity)
        }
        .heldButtonStyle()
    }

    private var summary: some View {
        let pendingFunds = AttentionEngine.funds(orders: activeOrders)
            .filter { $0.pendingMinor != 0 }

        return HeldCard {
            VStack(alignment: .leading, spacing: HeldSpacing.medium) {
                HStack(alignment: .firstTextBaseline) {
                    Text(activeOrders.isEmpty ? "Nothing open" : "\(activeOrders.count) \(activeOrders.count == 1 ? "open order" : "open orders")")
                        .heldTitle()
                        .foregroundStyle(HeldColor.ink)
                    Spacer()
                    Image(systemName: activeOrders.isEmpty ? "checkmark.circle" : "archivebox")
                        .foregroundStyle(HeldColor.accent)
                        .accessibilityHidden(true)
                }

                if pendingFunds.isEmpty {
                    Text(activeOrders.isEmpty
                         ? "Your delivered and resolved orders remain here whenever you need them."
                         : "Your open orders have no pending amount recorded.")
                        .heldBody()
                        .foregroundStyle(HeldColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: HeldSpacing.extraSmall) {
                        Text("Still in motion")
                            .heldCaption()
                            .foregroundStyle(HeldColor.secondaryInk)
                        ForEach(pendingFunds, id: \.currency) { funds in
                            Text(formatMoney(minor: funds.pendingMinor, currency: funds.currency))
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(HeldColor.accent)
                        }
                    }
                }

                if !attentionItems.isEmpty {
                    Text("\(attentionItems.count) \(attentionItems.count == 1 ? "order needs" : "orders need") a little attention.")
                        .heldCaption()
                        .foregroundStyle(HeldColor.secondaryInk)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var attentionSection: some View {
        VStack(alignment: .leading, spacing: HeldSpacing.medium) {
            HeldSectionHeader(
                title: "Needs attention",
                subtitle: attentionItems.isEmpty ? nil : "Ordered by the promise that calls for action first."
            )

            if attentionItems.isEmpty {
                HomeOrdersMessage(
                    title: "All quiet for now",
                    message: "No estimate, check-in, deadline, or partial delivery needs your attention."
                )
            } else {
                ForEach(attentionItems, id: \.order.id) { attention in
                    NavigationLink {
                        OrderDetailView(order: attention.order)
                    } label: {
                        HomeAttentionCard(attention: attention)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: HeldSpacing.medium) {
            HeldSectionHeader(
                title: "Recent orders",
                subtitle: "A little progress, without losing the story."
            )

            ForEach(Array(recentOrders.prefix(3)), id: \.id) { order in
                NavigationLink {
                    OrderDetailView(order: order)
                } label: {
                    HomeOrderCard(order: order)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func ensureSettingsExist() {
        guard settings.isEmpty else { return }
        do {
            _ = try AppSettings.fetchOrCreate(context: modelContext)
            try modelContext.save()
        } catch {
            // The in-memory fallback keeps Home usable if settings cannot be saved.
        }
    }

    private func attentionRank(_ kind: AttentionReasonKind) -> Int {
        switch kind {
        case .deadline: return 0
        case .estimate: return 1
        case .check: return 2
        case .partial: return 3
        case .stale: return 4
        }
    }
}

private struct HomeAttentionCard: View {
    let attention: OrderAttention

    var body: some View {
        HeldCard(padding: HeldSpacing.medium) {
            VStack(alignment: .leading, spacing: HeldSpacing.medium) {
                HStack(alignment: .top, spacing: HeldSpacing.medium) {
                    VStack(alignment: .leading, spacing: HeldSpacing.extraSmall) {
                        Text(attention.order.title)
                            .font(.headline)
                            .foregroundStyle(HeldColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(attention.order.vendor)
                            .heldCaption()
                            .foregroundStyle(HeldColor.secondaryInk)
                    }
                    Spacer(minLength: HeldSpacing.small)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HeldColor.secondaryInk)
                        .padding(.top, 3)
                        .accessibilityHidden(true)
                }

                ForEach(attention.reasons, id: \.kind) { reason in
                    HStack(alignment: .top, spacing: HeldSpacing.small) {
                        Image(systemName: reason.kind.symbolName)
                            .font(.subheadline)
                            .foregroundStyle(HeldColor.terracotta)
                            .frame(width: 22)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: HeldSpacing.extraSmall) {
                            Text(reason.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(HeldColor.ink)
                            Text(reason.description)
                                .heldCaption()
                                .foregroundStyle(HeldColor.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens order details")
        }
        .contentShape(Rectangle())
    }
}
