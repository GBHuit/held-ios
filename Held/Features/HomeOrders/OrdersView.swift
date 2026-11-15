import SwiftUI
import SwiftData

private enum OrdersFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case open = "Open"
    case delivered = "Delivered"
    case attention = "Attention"

    var id: String { rawValue }
}

struct OrdersView: View {
    @Query private var orders: [HeldOrder]
    @Query private var settings: [AppSettings]
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var reminderScheduler: ReminderScheduler

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
                .navigationTitle("Orders")
                .navigationBarTitleDisplayMode(.large)
                .searchable(
                    text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: "Title, vendor, or order number"
                )
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
                .alert("Delete this order?", isPresented: deletionAlertPresented) {
                    Button("Cancel", role: .cancel) {
                        orderPendingDeletion = nil
                    }
                    Button("Delete order", role: .destructive) {
                        guard let order = orderPendingDeletion else { return }
                        orderPendingDeletion = nil
                        Task { await delete(order) }
                    }
                    .disabled(isDeleting)
                } message: {
                    if let order = orderPendingDeletion {
                        Text("“\(order.title)” and its milestones, reminders, items, and saved attachments will be removed. This cannot be undone.")
                    }
                }
                .alert("Held couldn’t finish that", isPresented: errorAlertPresented) {
                    Button("OK") { actionErrorMessage = nil }
                } message: {
                    Text(actionErrorMessage ?? "Please try again.")
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
                title: "No orders yet",
                message: "When you add an order, Held will keep its promise, progress, and follow-ups together.",
                buttonTitle: "Add your first order",
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
                        title: "No matching orders",
                        message: "Try another search, or clear the filters to bring every order back.",
                        buttonTitle: "Clear search and filters",
                        action: clearSearchAndFilters
                    )
                } else {
                    List {
                        ForEach(filteredOrders, id: \.id) { order in
                            NavigationLink {
                                OrderDetailView(order: order)
                            } label: {
                                HomeOrderCard(order: order)
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
                                    Label("Delete", systemImage: "trash")
                                }
                                .accessibilityLabel("Delete \(order.title)")
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
                            Label(option.rawValue, systemImage: "checkmark")
                        } else {
                            Text(option.rawValue)
                        }
                    }
                }
            } label: {
                filterLabel(title: filter.rawValue, systemImage: "line.3.horizontal.decrease")
            }
            .accessibilityLabel("Order status filter")
            .accessibilityValue(filter.rawValue)

            Menu {
                Button {
                    currencyFilter = nil
                } label: {
                    if currencyFilter == nil {
                        Label("All currencies", systemImage: "checkmark")
                    } else {
                        Text("All currencies")
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
                filterLabel(title: currencyFilter?.rawValue ?? "Currency", systemImage: "coloncurrencysign.circle")
            }
            .accessibilityLabel("Currency filter")
            .accessibilityValue(currencyFilter?.rawValue ?? "All currencies")

            Spacer(minLength: 0)

            Text("\(filteredOrders.count) \(filteredOrders.count == 1 ? "order" : "orders")")
                .heldCaption()
                .foregroundStyle(HeldColor.secondaryInk)
                .accessibilityLabel("\(filteredOrders.count) matching orders")
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
            actionErrorMessage = "The order could not be deleted. Please try again."
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
            actionErrorMessage = "The order was deleted, but an orphaned attachment could not be removed. Your remaining orders are unaffected."
        }
    }
}
