import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var orders: [HeldOrder]
    @Query private var settings: [AppSettings]
    @StateObject private var reminders = ReminderScheduler()
    @StateObject private var purchases = PurchaseService()

    @State private var selectedTab = 0
    @State private var bootstrapError: String?
    @State private var hasBootstrapped = false

    private var preferredScheme: ColorScheme? {
        switch settings.first?.preferredColorSchemeRaw {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem { Label("Today", systemImage: "sun.horizon") }
                .tag(0)

            OrdersView()
                .tabItem { Label("Orders", systemImage: "shippingbox") }
                .tag(1)

            FundsView()
                .tabItem { Label("Funds", systemImage: "chart.bar") }
                .tag(2)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(3)
        }
        .tint(HeldColor.accent)
        .environmentObject(reminders)
        .environmentObject(purchases)
        .preferredColorScheme(preferredScheme)
        .task {
            guard !hasBootstrapped else { return }
            hasBootstrapped = true
            do {
                try SeedData.installIfNeeded(context: modelContext)
                let currentSettings = try AppSettings.fetchOrCreate(context: modelContext)
                selectedTab = min(3, max(0, currentSettings.lastSelectedTab))
                try modelContext.save()
                let persistedOrders = try modelContext.fetch(FetchDescriptor<HeldOrder>())
                await reminders.sync(orders: persistedOrders, settings: currentSettings)
                await purchases.synchronize(settings: currentSettings)
                try? modelContext.save()
            } catch {
                bootstrapError = "Held could not prepare local storage. Please restart the app. \(error.localizedDescription)"
            }
        }
        .onChange(of: selectedTab) { _, newValue in
            settings.first?.lastSelectedTab = newValue
            try? modelContext.save()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await reminders.refreshAuthorizationStatus()
                if let currentSettings = settings.first {
                    await reminders.sync(orders: orders, settings: currentSettings)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .heldOpenOrders)) { _ in
            selectedTab = 1
        }
        .alert("Local storage needs attention", isPresented: Binding(
            get: { bootstrapError != nil },
            set: { if !$0 { bootstrapError = nil } }
        )) {
            Button("OK", role: .cancel) { bootstrapError = nil }
        } message: {
            Text(bootstrapError ?? "")
        }
    }
}
