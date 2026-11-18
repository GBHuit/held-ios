import SwiftUI
import SwiftData

private enum OrdersFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case open = "Open"
    case delivered = "Delivered"
    case attention = "Attention"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return L("All")
        case .open: return L("Open")
        case .delivered: return L("Delivered")
        case .attention: return L("Attention")
        }
    }
}

struct OrdersView: View {
    @Query private var orders: [HeldOrder]
    @Query private var settings: [AppSettings]
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var reminderScheduler: ReminderScheduler
    @EnvironmentObject private var localization: LocalizationCenter

    @State private var searchText = ""
    @State private var filter: OrdersFilter = .all
    @State private var currencyFilter: CurrencyCode?
    @State private var showingAddOrder = false
    @State private var orderPendingDeletion: HeldOrder?
    @State private var actionErrorMessage: String?
    @State private var isDeleting = false

    private var currentSettings: AppSettings {
        settings.first ?? AppSettings()
    }

    private var attentionOrderIDs: Set<String> {
        Set(AttentionEngine.attention(orders: orders, settings: currentSettings).map { $0.order.id })
    }

    private var filteredOrders: [HeldOrder] {
        let query = HomeOrdersText.trimmed(searchText)
        let attentionIDs = attentionOrderIDs
        return orders.filter { order in
            let matchesSearch = query.isEmpty ||
                order.title.localizedCaseInsensitiveContains(query) ||
                order.vendor.localizedCaseInsensitiveContains(query) ||
                order.orderNumber.localizedCaseInsensitiveContains(query)

            let matchesFilter: Bool
            switch filter {
            case .all:
                matchesFilter = true
            case .open:
                matchesFilter = order.isActive
            case .delivered:
                matchesFilter = order.fulfillmentStatus == .delivered
            case .attention:
                matchesFilter = attentionIDs.contains(order.id)
            }

            let matchesCurrency = currencyFilter == nil || order.currencyCode == currencyFilter
            return matchesSearch && matchesFilter && matchesCurrency
        }
        .sorted { $0.orderedAt > $1.orderedAt }
    }

    private var deletionAlertPresented: Binding<Bool> {
        Binding(
            get: { orderPendingDeletion != nil },
            set: { if !$0 { orderPendingDeletion = nil } }
        )
    }

    private var errorAlertPresented: Binding<Bool> {
        Binding(
            get: { actionErrorMessage != nil },
            set: { if !$0 { actionErrorMessage = nil } }
        )
    }

    var body: some View {
        NavigationStack {
            content
                .heldScreenBackground()
                .navigationTitle(L("Orders"))
                .navigationBarTitleDisplayMode(.large)
                .searchable(
                    text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: L("Title, vendor, or order number")
                )
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingAddOrder = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel(L("Add a new order"))
                    }
                }
                .sheet(isPresented: $showingAddOrder) {
                    AddOrderView()
                }
                .alert(L("Delete this order?"), isPresented: deletionAlertPresented) {
                    Button(L("Cancel"), role: .cancel) {
                        orderPendingDeletion = nil
                    }
                    Button(L("Delete order"), role: .destructive) {
                        guard let order = orderPendingDeletion else { return }
                        orderPendingDeletion = nil
                        Task { await delete(order) }
                    }
                    .disabled(isDeleting)
                } message: {
                    if let order = orderPendingDeletion {
                        Text(L("“%1$@” and its milestones, reminders, items, and saved attachments will be removed. This cannot be undone.", order.title))
                    }
                }
                .alert(L("Keyvow couldn’t finish that"), isPresented: errorAlertPresented) {
                    Button(L("OK")) { actionErrorMessage = nil }
                } message: {
                    Text(actionErrorMessage ?? L("Please try again."))
                }
                .task {
                    ensureSettingsExist()
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if orders.isEmpty {
            HeldEmptyView(
                icon: "shippingbox",
                title: L("No orders yet"),
                message: L("When you add an order, Keyvow will keep its promise, progress, and follow-ups together."),
                buttonTitle: L("Add your first order"),
                action: { showingAddOrder = true }
            )
        } else {
            VStack(spacing: 0) {
                filterBar
                    .padding(.horizontal, HeldSpacing.medium)
                    .padding(.vertical, HeldSpacing.small)

                if filteredOrders.isEmpty {
                    HeldEmptyView(
                        icon: "line.3.horizontal.decrease.circle",
                        title: L("No matching orders"),
                        message: L("Try another search, or clear the filters to bring every order back."),
                        buttonTitle: L("Clear search and filters"),
                        action: clearSearchAndFilters
                    )
                } else {
                    List {
                        ForEach(filteredOrders, id: \.id) { order in
                            NavigationLink {
                                OrderDetailView(order: order)
                            } label: {
                                HomeOrderCard(order: order, showsChevron: false)
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(
                                top: HeldSpacing.small,
                                leading: HeldSpacing.medium,
                                bottom: HeldSpacing.small,
                                trailing: HeldSpacing.medium
                            ))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    orderPendingDeletion = order
                                } label: {
                                    Label(L("Delete"), systemImage: "trash")
                                }
                                .accessibilityLabel(L("Delete %@", order.title))
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: HeldSpacing.small) {
            Menu {
                ForEach(OrdersFilter.allCases) { option in
                    Button {
                        filter = option
                    } label: {
                        if filter == option {
                            Label(option.displayName, systemImage: "checkmark")
                        } else {
                            Text(option.displayName)
                        }
                    }
                }
            } label: {
                filterLabel(title: filter.displayName, systemImage: "line.3.horizontal.decrease")
            }
            .accessibilityLabel(L("Order status filter"))
            .accessibilityValue(filter.displayName)

            Menu {
                Button {
                    currencyFilter = nil
                } label: {
                    if currencyFilter == nil {
                        Label(L("All currencies"), systemImage: "checkmark")
                    } else {
                        Text(L("All currencies"))
                    }
                }
                ForEach(CurrencyCode.allCases, id: \.self) { currency in
                    Button {
                        currencyFilter = currency
                    } label: {
                        if currencyFilter == currency {
                            Label(currency.rawValue, systemImage: "checkmark")
                        } else {
                            Text(currency.rawValue)
                        }
                    }
                }
            } label: {
                filterLabel(title: currencyFilter?.rawValue ?? L("Currency"), systemImage: "coloncurrencysign.circle")
            }
            .accessibilityLabel(L("Currency filter"))
            .accessibilityValue(currencyFilter?.rawValue ?? L("All currencies"))

            Spacer(minLength: 0)

            Text(L(filteredOrders.count == 1 ? "%1$lld order" : "%1$lld orders", Int64(filteredOrders.count)))
                .heldCaption()
                .foregroundStyle(HeldColor.secondaryInk)
                .accessibilityLabel(L("%1$lld matching orders", Int64(filteredOrders.count)))
        }
    }

    private func filterLabel(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(HeldColor.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .background(HeldColor.surface, in: Capsule())
            .overlay {
                Capsule().strokeBorder(HeldColor.separator, lineWidth: 0.75)
            }
    }

    private func clearSearchAndFilters() {
        searchText = ""
        filter = .all
        currencyFilter = nil
    }

    private func ensureSettingsExist() {
        guard settings.isEmpty else { return }
        do {
            _ = try AppSettings.fetchOrCreate(context: modelContext)
            try modelContext.save()
        } catch {
            // AttentionEngine can still use its default settings for this session.
        }
    }

    @MainActor
    private func delete(_ order: HeldOrder) async {
        guard !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }

        let orderID = order.id
        let attachmentPaths = Set(order.evidence.compactMap(\.localRelativePath))

        // Persist the graph deletion before touching originals. If a database
        // save fails, every attachment must still be available for the order.
        modelContext.delete(order)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            actionErrorMessage = L("The order could not be deleted. Please try again.")
            return
        }

        await reminderScheduler.cancel(orderID: orderID)

        // Orphaned files are preferable to lost evidence if cleanup itself
        // fails, and can be reclaimed by a later storage-maintenance pass.
        do {
            let store = try AttachmentStore()
            for path in attachmentPaths {
                try store.remove(relativePath: path)
            }
        } catch {
            actionErrorMessage = L("The order was deleted, but an orphaned attachment could not be removed. Your remaining orders are unaffected.")
        }
    }
}
