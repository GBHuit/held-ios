import SwiftUI
import SwiftData
import PhotosUI

private enum AddOrderStep: Int, CaseIterable {
    case basics
    case promise
    case itemsAndReminder

    var title: String {
        switch self {
        case .basics: return "Basics"
        case .promise: return "Promise"
        case .itemsAndReminder: return "Items & reminder"
        }
    }
}

private struct AddOrderItemDraft: Identifiable {
    let id = UUID()
    var name = ""
    var variant = ""
    var quantityText = "1"
    var amountText = ""
}

private struct AddOrderInputError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

struct AddOrderView: View {
    @Query private var orders: [HeldOrder]
    @Query private var settings: [AppSettings]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var reminderScheduler: ReminderScheduler

    @State private var step: AddOrderStep = .basics

    @State private var title = ""
    @State private var vendor = ""
    @State private var orderNumber = ""
    @State private var orderDate = Date()
    @State private var amountText = ""
    @State private var currency: CurrencyCode = .USD
    @State private var paymentMethod = ""
    @State private var sourceURL = ""

    @State private var estimateText = ""
    @State private var hasEstimateEnd = false
    @State private var estimateEnd = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    @State private var trackingNumber = ""
    @State private var carrier = ""

    @State private var itemDrafts: [AddOrderItemDraft] = []
    @State private var nextCheckEnabled = true
    @State private var nextCheckAt = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var deadlineReminderEnabled = false
    @State private var deadlineReminderAt = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
    @State private var deadlineLeadDays = 7

    @State private var validationMessage: String?
    @State private var isSaving = false
    @State private var didLoadReminderSettings = false

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isRecognizing = false
    @State private var ocrResult: OCRResult?
    @State private var ocrStatusMessage: String?

    private var ocrReviewPresented: Binding<Bool> {
        Binding(
            get: { ocrResult != nil },
            set: { if !$0 { ocrResult = nil } }
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progressIndicator
                    .padding(.horizontal, HeldSpacing.medium)
                    .padding(.vertical, HeldSpacing.medium)
                    .background(HeldColor.background)

                Form {
                    switch step {
                    case .basics:
                        basicsSection
                    case .promise:
                        promiseSection
                    case .itemsAndReminder:
                        itemsAndReminderSection
                    }
                }
                .scrollContentBackground(.hidden)
                .background(HeldColor.background)
                .scrollDismissesKeyboard(.interactively)
            }
            .heldScreenBackground()
            .navigationTitle("New order")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomControls
            }
            .interactiveDismissDisabled(isSaving)
            .heldLoadingOverlay(isPresented: isSaving, title: "Saving your order…")
            .sheet(isPresented: ocrReviewPresented) {
                if let ocrResult {
                    OCRReviewView(
                        result: ocrResult,
                        onApply: applyOCRSuggestions,
                        onCancel: { self.ocrResult = nil }
                    )
                }
            }
            .onChange(of: selectedPhoto) { _, newValue in
                guard let newValue else { return }
                Task { await recognizePhoto(newValue) }
            }
            .task {
                ensureSettingsExist()
            }
        }
    }

    private var progressIndicator: some View {
        VStack(alignment: .leading, spacing: HeldSpacing.small) {
            HStack(spacing: HeldSpacing.small) {
                ForEach(AddOrderStep.allCases, id: \.rawValue) { item in
                    Capsule()
                        .fill(item.rawValue <= step.rawValue ? HeldColor.accent : HeldColor.separator)
                        .frame(height: 4)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)

            Text("\(step.title) — Step \(step.rawValue + 1) of \(AddOrderStep.allCases.count)")
                .heldCaption()
                .foregroundStyle(HeldColor.secondaryInk)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step.rawValue + 1) of \(AddOrderStep.allCases.count): \(step.title)")
    }

    @ViewBuilder
    private var basicsSection: some View {
        Section {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label("Read a receipt or confirmation", systemImage: "doc.text.viewfinder")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 44)
            }
            .disabled(isRecognizing)

            if isRecognizing {
                HStack(spacing: HeldSpacing.small) {
                    ProgressView()
                    Text("Looking for order details…")
                        .foregroundStyle(HeldColor.secondaryInk)
                }
                .accessibilityElement(children: .combine)
            }

            Text("OCR suggestions need your confirmation. Nothing is added to the form until you review them.")
                .heldCaption()
                .foregroundStyle(HeldColor.secondaryInk)

            if let ocrStatusMessage {
                Text(ocrStatusMessage)
                    .heldCaption()
                    .foregroundStyle(HeldColor.secondaryInk)
            }
        } header: {
            Text("Start with a photo — optional")
        } footer: {
            Text("No image? Continue with the manual fields below. Camera evidence scanning remains available in order details.")
        }

        Section {
            TextField("Order title", text: $title, axis: .vertical)
                .textInputAutocapitalization(.words)
            TextField("Vendor", text: $vendor)
                .textInputAutocapitalization(.words)
            TextField("Order number — optional", text: $orderNumber)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            DatePicker("Order date", selection: $orderDate, displayedComponents: .date)
        } header: {
            Text("The essentials")
        } footer: {
            Text("Title and vendor are required.")
        }

        Section {
            TextField("Amount — for example, 249.00", text: $amountText)
                .keyboardType(.decimalPad)
            Picker("Currency", selection: $currency) {
                ForEach(CurrencyCode.allCases, id: \.self) { code in
                    Text(code.rawValue).tag(code)
                }
            }
            TextField("Payment method — optional", text: $paymentMethod)
            TextField("Order or listing URL — optional", text: $sourceURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text("Payment")
        } footer: {
            Text("Leave the amount blank if it is not known yet. Amounts are stored as exact minor units.")
        }
    }

    @ViewBuilder
    private var promiseSection: some View {
        Section {
            TextField(
                "Original estimate — for example, “Ships in 8–10 weeks”",
                text: $estimateText,
                axis: .vertical
            )
            .lineLimit(3...7)

            Toggle("Include an estimated end date", isOn: $hasEstimateEnd)
            if hasEstimateEnd {
                DatePicker("Estimated end", selection: $estimateEnd, displayedComponents: .date)
            }
        } header: {
            Text("The original promise")
        } footer: {
            Text("Held saves this wording with the purchase milestone. Later updates will not rewrite the original promise.")
        }

        Section {
            TextField("Tracking number — optional", text: $trackingNumber)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("Carrier — optional", text: $carrier)
        } header: {
            Text("Shipping — optional")
        }
    }

    @ViewBuilder
    private var itemsAndReminderSection: some View {
        Section {
            if itemDrafts.isEmpty {
                Text("No line items yet. You can save without them, or add the items that make up this order.")
                    .heldBody()
                    .foregroundStyle(HeldColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach($itemDrafts) { $item in
                VStack(alignment: .leading, spacing: HeldSpacing.small) {
                    HStack {
                        Text("Item")
                            .font(.headline)
                        Spacer()
                        Button("Remove", role: .destructive) {
                            itemDrafts.removeAll { $0.id == item.id }
                        }
                        .font(.subheadline)
                        .frame(minWidth: 44, minHeight: 44)
                    }

                    TextField("Item name", text: $item.name)
                    TextField("Variant — optional", text: $item.variant)
                    TextField("Quantity", text: $item.quantityText)
                        .keyboardType(.numberPad)
                    TextField("Line amount in \(currency.rawValue) — optional", text: $item.amountText)
                        .keyboardType(.decimalPad)
                }
                .padding(.vertical, HeldSpacing.extraSmall)
            }

            Button {
                itemDrafts.append(AddOrderItemDraft())
            } label: {
                Label("Add an item", systemImage: "plus")
                    .frame(minHeight: 44)
            }
        } header: {
            Text("Items — optional")
        } footer: {
            Text("Each item needs a name and a quantity of at least 1. A line amount is the total for that line, not a unit price.")
        }

        Section {
            Toggle("Check in on this order", isOn: $nextCheckEnabled)
            if nextCheckEnabled {
                DatePicker(
                    "Next check-in",
                    selection: $nextCheckAt,
                    displayedComponents: [.date, .hourAndMinute]
                )
            }

            Toggle("Add a deadline reminder", isOn: $deadlineReminderEnabled)
            if deadlineReminderEnabled {
                DatePicker(
                    "Reminder date",
                    selection: $deadlineReminderAt,
                    displayedComponents: [.date, .hourAndMinute]
                )
                Stepper("Lead time: \(deadlineLeadDays) \(deadlineLeadDays == 1 ? "day" : "days")", value: $deadlineLeadDays, in: 0...90)
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text("New orders include a check-in by default. Notifications follow your Held settings; reminder dates are saved even when system notifications are off.")
        }
    }

    private var bottomControls: some View {
        VStack(spacing: HeldSpacing.small) {
            if let validationMessage {
                Text(validationMessage)
                    .heldCaption()
                    .foregroundStyle(HeldColor.danger)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.updatesFrequently)
            }

            HStack(spacing: HeldSpacing.medium) {
                if step != .basics {
                    Button("Back") {
                        validationMessage = nil
                        step = AddOrderStep(rawValue: step.rawValue - 1) ?? .basics
                    }
                    .heldButtonStyle(.secondary)
                    .disabled(isSaving)
                }

                Spacer(minLength: 0)

                if step == .itemsAndReminder {
                    Button("Save order") {
                        Task { await saveOrder() }
                    }
                    .heldButtonStyle()
                    .disabled(isSaving || isRecognizing)
                } else {
                    Button("Continue") {
                        continueToNextStep()
                    }
                    .heldButtonStyle()
                    .disabled(isSaving)
                }
            }
        }
        .padding(.horizontal, HeldSpacing.medium)
        .padding(.vertical, HeldSpacing.small)
        .background(HeldColor.background.ignoresSafeArea(edges: .bottom))
    }

    private func continueToNextStep() {
        do {
            if step == .basics {
                try validateBasics()
            }
            validationMessage = nil
            step = AddOrderStep(rawValue: step.rawValue + 1) ?? .itemsAndReminder
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func validateBasics() throws {
        guard !HomeOrdersText.trimmed(title).isEmpty else {
            throw AddOrderInputError("Enter an order title before continuing.")
        }
        guard !HomeOrdersText.trimmed(vendor).isEmpty else {
            throw AddOrderInputError("Enter the vendor before continuing.")
        }
        let trimmedURL = HomeOrdersText.trimmed(sourceURL)
        if !trimmedURL.isEmpty {
            guard let url = URL(string: trimmedURL),
                  let scheme = url.scheme?.lowercased(),
                  ["http", "https"].contains(scheme),
                  url.host != nil else {
                throw AddOrderInputError("Enter a complete http or https order URL, or leave the URL blank.")
            }
        }
        _ = try AddOrderMoney.minorUnits(from: amountText, fieldName: "Order amount")
    }

    private func validateItems() throws {
        for (index, item) in itemDrafts.enumerated() {
            let itemNumber = index + 1
            guard !HomeOrdersText.trimmed(item.name).isEmpty else {
                throw AddOrderInputError("Enter a name for item \(itemNumber), or remove that item.")
            }
            guard let quantity = Int(HomeOrdersText.trimmed(item.quantityText)), quantity >= 1 else {
                throw AddOrderInputError("Item \(itemNumber) needs a quantity of at least 1.")
            }
            _ = try AddOrderMoney.minorUnits(from: item.amountText, fieldName: "Amount for item \(itemNumber)")
        }
    }

    private func ensureSettingsExist() {
        if !didLoadReminderSettings {
            deadlineLeadDays = min(90, max(0, settings.first?.leadDays ?? 7))
            didLoadReminderSettings = true
        }
        guard settings.isEmpty else { return }
        do {
            _ = try AppSettings.fetchOrCreate(context: modelContext)
            try modelContext.save()
        } catch {
            // Saving the order will try again and report any persistent storage error.
        }
    }

    @MainActor
    private func saveOrder() async {
        do {
            try validateBasics()
            try validateItems()
        } catch {
            validationMessage = error.localizedDescription
            return
        }

        validationMessage = nil
        isSaving = true
        defer { isSaving = false }

        do {
            let trimmedTitle = HomeOrdersText.trimmed(title)
            let trimmedVendor = HomeOrdersText.trimmed(vendor)
            let trimmedEstimate = HomeOrdersText.trimmed(estimateText)
            let trimmedSourceURL = HomeOrdersText.trimmed(sourceURL)
            let amountMinor = try AddOrderMoney.minorUnits(from: amountText, fieldName: "Order amount") ?? 0

            let order = HeldOrder(
                title: trimmedTitle,
                vendor: trimmedVendor,
                orderNumber: HomeOrdersText.trimmed(orderNumber),
                orderedAt: orderDate,
                amountMinor: amountMinor,
                currencyCode: currency,
                paymentMethod: HomeOrdersText.trimmed(paymentMethod),
                sourceURL: trimmedSourceURL,
                estimateText: trimmedEstimate,
                fulfillmentStatus: .ordered,
                resolutionStatus: .none,
                estimateEnd: hasEstimateEnd ? estimateEnd : nil,
                nextCheckAt: nextCheckEnabled ? nextCheckAt : nil,
                trackingNumber: HomeOrdersText.trimmed(trackingNumber),
                carrier: HomeOrdersText.trimmed(carrier)
            )

            var items: [OrderItem] = []
            for draft in itemDrafts {
                guard let quantity = Int(HomeOrdersText.trimmed(draft.quantityText)) else { continue }
                let itemAmount = try AddOrderMoney.minorUnits(
                    from: draft.amountText,
                    fieldName: "Item amount"
                )
                items.append(OrderItem(
                    name: HomeOrdersText.trimmed(draft.name),
                    variant: HomeOrdersText.trimmed(draft.variant),
                    quantity: quantity,
                    amountMinor: itemAmount,
                    order: order
                ))
            }
            order.items = items

            let purchase = Milestone(
                kind: .purchase,
                occurredAt: orderDate,
                title: "Order placed",
                note: trimmedEstimate.isEmpty
                    ? "Original purchase details recorded in Held."
                    : trimmedEstimate,
                sourceURL: trimmedSourceURL.isEmpty ? nil : trimmedSourceURL,
                order: order
            )
            order.milestones = [purchase]

            var reminders: [HeldReminder] = []
            if nextCheckEnabled {
                reminders.append(HeldReminder(
                    kind: .checkIn,
                    triggerAt: nextCheckAt,
                    leadDays: 0,
                    enabled: true,
                    label: "Check in with \(trimmedVendor)",
                    order: order
                ))
            }
            if deadlineReminderEnabled {
                reminders.append(HeldReminder(
                    kind: .deadline,
                    triggerAt: deadlineReminderAt,
                    leadDays: deadlineLeadDays,
                    enabled: true,
                    label: "Review the deadline for \(trimmedTitle)",
                    order: order
                ))
            }
            order.reminders = reminders

            let appSettings = try AppSettings.fetchOrCreate(context: modelContext)
            modelContext.insert(order)
            try modelContext.save()

            let ordersForSync = orders.contains { $0.id == order.id } ? orders : orders + [order]
            await reminderScheduler.sync(orders: ordersForSync, settings: appSettings)
            dismiss()
        } catch {
            modelContext.rollback()
            validationMessage = "The order could not be saved. Please check the details and try again."
        }
    }

    private func recognizePhoto(_ item: PhotosPickerItem) async {
        isRecognizing = true
        ocrStatusMessage = nil
        defer {
            isRecognizing = false
            selectedPhoto = nil
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self), !data.isEmpty else {
                ocrStatusMessage = "No readable image was selected. Continue with the manual form below."
                return
            }
            let result = try await OCREngine().recognizeText(data: data)
            ocrResult = result
        } catch {
            ocrStatusMessage = "Text recognition could not read this image. \(error.localizedDescription) You can continue manually."
        }
    }

    private func applyOCRSuggestions(_ suggestions: OCRConfirmedSuggestions) {
        if let suggestedOrderNumber = suggestions.orderNumber {
            orderNumber = suggestedOrderNumber
        }
        if let suggestedOrderDate = suggestions.orderDate {
            orderDate = suggestedOrderDate
        }
        if let suggestedAmount = suggestions.amount {
            amountText = NSDecimalNumber(decimal: suggestedAmount).stringValue
        }
        if let suggestedCurrency = suggestions.currency {
            currency = suggestedCurrency
        }
        ocrResult = nil
        ocrStatusMessage = "OCR suggestions applied. Review the updated fields before saving."
        validationMessage = nil
    }
}

private enum AddOrderMoney {
    private static let posixLocale = Locale(identifier: "en_US_POSIX")
    private static let amountPattern = #"^\+?(?:(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d{0,2})?|\.\d{1,2})$"#

    static func minorUnits(from text: String, fieldName: String) throws -> Int64? {
        let trimmed = HomeOrdersText.trimmed(text)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.range(of: amountPattern, options: .regularExpression) != nil else {
            throw AddOrderInputError("\(fieldName) must be a non-negative amount with no more than two decimal places.")
        }

        let normalized = trimmed
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "+", with: "")
        guard let decimal = Decimal(string: normalized, locale: posixLocale),
              !decimal.isNaN,
              decimal >= 0 else {
            throw AddOrderInputError("\(fieldName) could not be read as an amount.")
        }

        var unrounded = decimal * Decimal(100)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &unrounded, 0, .plain)
        guard !rounded.isNaN, rounded <= Decimal(Int64.max) else {
            throw AddOrderInputError("\(fieldName) is too large to store safely.")
        }

        let minorString = NSDecimalNumber(decimal: rounded).stringValue
        guard let minor = Int64(minorString) else {
            throw AddOrderInputError("\(fieldName) is too large to store safely.")
        }
        return minor
    }
}
