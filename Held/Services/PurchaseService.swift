import Foundation
import StoreKit
import Combine

@MainActor
final class PurchaseService: ObservableObject {
    static let lifetimeProductID = "held.pro"

    @Published private(set) var product: Product?
    @Published private(set) var isLoading = false
    @Published private(set) var isPro = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var statusMessage: String?

    private var updatesTask: Task<Void, Never>?
    private weak var registeredSettings: AppSettings?

    var displayPrice: String? { product?.displayPrice }

    var isAvailable: Bool { product != nil }

    init() {
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                await self.handle(transactionUpdate: result)
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func loadProduct() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let products = try await Product.products(for: [Self.lifetimeProductID])
            product = products.first(where: { $0.id == Self.lifetimeProductID && $0.type == .nonConsumable })
            if product == nil {
                errorMessage = "Held Pro is not available in the App Store right now."
            }
        } catch {
            product = nil
            errorMessage = "The App Store could not be reached. Check your connection and try again."
        }
    }

    /// Purchases the verified lifetime entitlement and updates the supplied
    /// settings only after StoreKit verification. Pending and cancelled
    /// purchases return false and never unlock Pro.
    @discardableResult
    func purchase(settings: AppSettings) async -> Bool {
        registeredSettings = settings
        errorMessage = nil
        statusMessage = nil
        isLoading = true
        defer { isLoading = false }

        if product == nil {
            do {
                let products = try await Product.products(for: [Self.lifetimeProductID])
                product = products.first(where: { $0.id == Self.lifetimeProductID && $0.type == .nonConsumable })
            } catch {
                errorMessage = "The App Store could not be reached. Check your connection and try again."
                return false
            }
        }
        guard let product else {
            errorMessage = "Held Pro is not available in the App Store right now."
            return false
        }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try Self.verifiedTransaction(from: verification)
                await transaction.finish()
                isPro = true
                settings.proUnlocked = true
                statusMessage = "Held Pro is unlocked. Thank you."
                return true
            case .userCancelled:
                statusMessage = "The purchase was cancelled."
                return false
            case .pending:
                statusMessage = "The purchase is pending approval. Pro will unlock only after the transaction is approved."
                return false
            @unknown default:
                errorMessage = "The App Store returned an unsupported purchase result."
                return false
            }
        } catch PurchaseServiceError.unverifiedTransaction {
            errorMessage = "The purchase could not be verified. Pro has not been unlocked."
            return false
        } catch {
            errorMessage = "The purchase could not be completed. Please try again."
            return false
        }
    }

    /// Restores App Store transactions and returns whether a verified Held Pro
    /// entitlement exists. A missing purchase is not reported as success.
    @discardableResult
    func restorePurchases(settings: AppSettings) async -> Bool {
        registeredSettings = settings
        isLoading = true
        errorMessage = nil
        statusMessage = nil
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            settings.proUnlocked = isPro
            statusMessage = isPro
                ? "Held Pro was restored."
                : "No Held Pro purchase was found for this App Store account."
            return isPro
        } catch {
            errorMessage = "Purchases could not be restored. Check your App Store connection and try again."
            return false
        }
    }

    /// Re-reads current entitlements and mirrors only the verified result into
    /// SwiftData settings. Call at launch and when the app returns to foreground.
    func synchronize(settings: AppSettings) async {
        registeredSettings = settings
        await refreshEntitlements()
        settings.proUnlocked = isPro
    }

    func refreshEntitlements() async {
        var foundVerifiedEntitlement = false
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? Self.verifiedTransaction(from: result) else { continue }
            if transaction.productID == Self.lifetimeProductID && transaction.revocationDate == nil {
                foundVerifiedEntitlement = true
                break
            }
        }
        isPro = foundVerifiedEntitlement
    }

    private func handle(transactionUpdate result: VerificationResult<Transaction>) async {
        do {
            let transaction = try Self.verifiedTransaction(from: result)
            guard transaction.productID == Self.lifetimeProductID else { return }
            await transaction.finish()
            await refreshEntitlements()
            registeredSettings?.proUnlocked = isPro
            if transaction.revocationDate != nil {
                statusMessage = "The Held Pro purchase is no longer active."
            } else if isPro {
                statusMessage = "Held Pro is unlocked."
            }
        } catch {
            errorMessage = "An App Store transaction could not be verified."
        }
    }

    private static func verifiedTransaction(
        from result: VerificationResult<Transaction>
    ) throws -> Transaction {
        switch result {
        case .verified(let transaction):
            return transaction
        case .unverified:
            throw PurchaseServiceError.unverifiedTransaction
        }
    }
}

private enum PurchaseServiceError: Error {
    case unverifiedTransaction
}
