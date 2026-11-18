import SwiftUI

// MARK: - Scalar order editing

struct OrderEditDraft {
    var title: String
    var vendor: String
    var orderNumber: String
    var orderedAt: Date
    var amountText: String
    var currencyCode: CurrencyCode
    var paymentMethod: String
    var sourceURL: String
    var estimateStart: Date?
    var estimateEnd: Date?
    var estimatePrecision: EstimatePrecision
    var estimateReferenceDate: Date
    var nextCheckAt: Date?
    var estimateRevisionNote: String
}

struct EditOrderSheet: View {
    @EnvironmentObject private var localization: LocalizationCenter
    let order: HeldOrder
    let onSave: (OrderEditDraft) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: OrderEditDraft
    @State private var hasNextCheck: Bool
    @State private var errorMessage: String?

    init(order: HeldOrder, onSave: @escaping (OrderEditDraft) throws -> Void) {
        self.order = order
        self.onSave = onSave
        let draft = OrderEditDraft(
            title: order.title,
            vendor: order.vendor,
            orderNumber: order.orderNumber,
            orderedAt: order.orderedAt,
            amountText: OrderDetailValidation.majorUnits(minor: order.amountMinor),
            currencyCode: order.currencyCode,
            paymentMethod: order.paymentMethod,
            sourceURL: order.sourceURL,
            estimateStart: order.estimateStart ?? order.estimateEnd,
            estimateEnd: order.estimateEnd,
            estimatePrecision: order.estimatePrecision,
            estimateReferenceDate: order.estimateStart ?? order.estimateEnd ?? Date(),
            nextCheckAt: order.nextCheckAt,
            estimateRevisionNote: ""
        )
        _draft = State(initialValue: draft)
        _hasNextCheck = State(initialValue: order.nextCheckAt != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L("Order")) {
                    TextField(L("Title"), text: $draft.title)
                        .textInputAutocapitalization(.words)
                    TextField(L("Vendor"), text: $draft.vendor)
                        .textInputAutocapitalization(.words)
                    TextField(L("Order number"), text: $draft.orderNumber)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    DatePicker(L("Ordered at"), selection: $draft.orderedAt)
                }

                Section(L("Amount & payment")) {
                    HStack {
                        TextField(L("Amount"), text: $draft.amountText)
                            .keyboardType(.decimalPad)
                            .accessibilityLabel(L("Order amount"))
                        Picker(L("Currency"), selection: $draft.currencyCode) {
                            ForEach(CurrencyCode.allCases, id: \.self) { currency in
                                Text(currency.displayLabel).tag(currency)
                            }
                        }
                        .labelsHidden()
                        .accessibilityLabel(L("Currency"))
                    }
                    TextField(L("Payment method"), text: $draft.paymentMethod)
                }

                Section(L("Source")) {
                    TextField("https://example.com/order", text: $draft.sourceURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    OrderDetailCallout(
                        title: L("Original estimate is immutable"),
                        message: order.estimateText.isEmpty
                            ? L("No original estimate text is recorded. A date revision creates a milestone and leaves this field untouched.")
                            : order.estimateText,
                        symbolName: "lock.fill",
                        tone: .warning
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)

                    Picker(L("Estimate precision"), selection: $draft.estimatePrecision) {
                        ForEach(EstimatePrecision.allCases, id: \.self) { precision in
                            Text(localizedEstimatePrecisionLabel(precision)).tag(precision)
                        }
                    }
                    estimateFields
                    TextField(L("Revision note (optional)"), text: $draft.estimateRevisionNote, axis: .vertical)
                        .lineLimit(2...5)
                    Text(L("Saving a changed estimate or precision adds a timeline milestone. Original estimate text and original evidence are never overwritten."))
                        .heldCaption()
                        .foregroundStyle(HeldColor.secondaryInk)
                } header: {
                    Text(L("Current estimate"))
                } footer: {
                    Text(L("Month, quarter, and season remain approximate in display. Attention is based on the end of the stored range."))
                }

                Section(L("Next check")) {
                    Toggle(L("Schedule next check"), isOn: $hasNextCheck.animation())
                    if hasNextCheck {
                        DatePicker(
                            L("Next check"),
                            selection: nextCheckBinding,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                }
            }
            .navigationTitle(L("Edit order"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Save"), action: save)
                }
            }
            .alert(L("Couldn’t save order"), isPresented: errorPresented) {
                Button(L("OK")) { errorMessage = nil }
            } message: {
                Text(L(errorMessage ?? "Unknown error"))
            }
        }
    }

    @ViewBuilder
    private var estimateFields: some View {
        switch draft.estimatePrecision {
        case .unknown:
            Text(L("No estimated dates will be stored."))
                .heldCaption()
                .foregroundStyle(HeldColor.secondaryInk)
        case .day:
            DatePicker(L("Estimated start"), selection: estimateStartBinding, displayedComponents: .date)
            DatePicker(L("Estimated end"), selection: estimateEndBinding, displayedComponents: .date)
        case .month:
            DatePicker(L("Any date in the estimated month"), selection: $draft.estimateReferenceDate, displayedComponents: .date)
        case .quarter:
            DatePicker(L("Any date in the estimated quarter"), selection: $draft.estimateReferenceDate, displayedComponents: .date)
        case .season:
            DatePicker(L("Any date in the estimated season"), selection: $draft.estimateReferenceDate, displayedComponents: .date)
            Text(L("Seasons use meteorological boundaries: March–May, June–August, September–November, and December–February."))
                .heldCaption()
                .foregroundStyle(HeldColor.secondaryInk)
        }
    }

    private var estimateStartBinding: Binding<Date> {
        Binding(
            get: { draft.estimateStart ?? draft.estimateEnd ?? Date() },
            set: { draft.estimateStart = $0 }
        )
    }

    private var estimateEndBinding: Binding<Date> {
        Binding(
            get: { draft.estimateEnd ?? draft.estimateStart ?? Date() },
            set: { draft.estimateEnd = $0 }
        )
    }

    private var nextCheckBinding: Binding<Date> {
        Binding(
            get: { draft.nextCheckAt ?? Date() },
            set: { draft.nextCheckAt = $0 }
        )
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func save() {
        let range = DeliveryEstimate.resolve(
            precision: draft.estimatePrecision,
            start: draft.estimateStart,
            end: draft.estimateEnd,
            referenceDate: draft.estimateReferenceDate
        )
        guard range.isChronological else {
            errorMessage = L("Estimated start must be on or before estimated end.")
            return
        }
        draft.estimateStart = range.start
        draft.estimateEnd = range.end
        draft.nextCheckAt = hasNextCheck ? (draft.nextCheckAt ?? Date()) : nil
        do {
            try onSave(draft)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Delivery editing

struct OrderItemDeliveryDraft: Identifiable {
    let id: String
    let name: String
    let variant: String
    let quantity: Int
    var deliveredQuantity: Int
    var status: ItemStatus
}

struct UpdateDeliverySheet: View {
    @EnvironmentObject private var localization: LocalizationCenter
    let onSave: ([OrderItemDeliveryDraft]) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [OrderItemDeliveryDraft]
    @State private var errorMessage: String?

    init(items: [OrderItem], onSave: @escaping ([OrderItemDeliveryDraft]) throws -> Void) {
        self.onSave = onSave
        _drafts = State(initialValue: items.map {
            OrderItemDeliveryDraft(
                id: $0.id,
                name: $0.name,
                variant: $0.variant,
                quantity: max(0, $0.quantity),
                deliveredQuantity: min(max(0, $0.deliveredQuantity), max(0, $0.quantity)),
                status: $0.status
            )
        })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(L("An order without line items can be marked Delivered directly. With items, Delivered is derived when every noncancelled item has its full quantity delivered. Any shipped or partially delivered item otherwise keeps the order partially shipped."))
                        .heldCaption()
                        .foregroundStyle(HeldColor.secondaryInk)
                }

                ForEach($drafts) { $draft in
                    Section {
                        if !draft.variant.isEmpty {
                            Text(draft.variant)
                                .heldCaption()
                                .foregroundStyle(HeldColor.secondaryInk)
                        }
                        Stepper(value: deliveredBinding(for: $draft), in: 0...max(0, draft.quantity)) {
                            Text(L("%1$lld of %2$lld delivered", draft.deliveredQuantity, draft.quantity))
                                .font(.headline.monospacedDigit())
                        }
                        .accessibilityLabel(L("Delivered quantity for %@", draft.name))
                        Picker(L("Item status"), selection: statusBinding(for: $draft)) {
                            ForEach(ItemStatus.allCases, id: \.self) { status in
                                Text(localizedItemStatusLabel(status)).tag(status)
                            }
                        }
                    } header: {
                        Text(draft.name)
                    }
                }
            }
            .navigationTitle(L("Update delivery"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Save"), action: save)
                }
            }
            .alert(L("Couldn’t update delivery"), isPresented: errorPresented) {
                Button(L("OK")) { errorMessage = nil }
            } message: {
                Text(L(errorMessage ?? "Unknown error"))
            }
        }
    }

    private func deliveredBinding(for draft: Binding<OrderItemDeliveryDraft>) -> Binding<Int> {
        Binding(
            get: { draft.wrappedValue.deliveredQuantity },
            set: { newValue in
                draft.wrappedValue.deliveredQuantity = newValue
                let quantity = draft.wrappedValue.quantity
                if newValue == quantity, quantity > 0,
                   draft.wrappedValue.status != .cancelled,
                   draft.wrappedValue.status != .refunded {
                    draft.wrappedValue.status = .delivered
                } else if draft.wrappedValue.status == .delivered, newValue < quantity {
                    draft.wrappedValue.status = newValue > 0 ? .shipped : .pending
                }
            }
        )
    }

    private func statusBinding(for draft: Binding<OrderItemDeliveryDraft>) -> Binding<ItemStatus> {
        Binding(
            get: { draft.wrappedValue.status },
            set: { newValue in
                draft.wrappedValue.status = newValue
                if newValue == .delivered {
                    draft.wrappedValue.deliveredQuantity = draft.wrappedValue.quantity
                }
            }
        )
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func save() {
        do {
            try onSave(drafts)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Milestones

struct MilestoneDraft {
    var kind = MilestoneKind.update
    var occurredAt = Date()
    var title = ""
    var note = ""
    var sourceURL = ""
}

struct AddMilestoneSheet: View {
    @EnvironmentObject private var localization: LocalizationCenter
    let onSave: (MilestoneDraft) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = MilestoneDraft()
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(L("Milestone")) {
                    Picker(L("Kind"), selection: $draft.kind) {
                        ForEach(MilestoneKind.allCases, id: \.self) { kind in
                            Label(localizedMilestoneKindLabel(kind), systemImage: kind.symbolName).tag(kind)
                        }
                    }
                    DatePicker(
                        L("Date"),
                        selection: $draft.occurredAt,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    TextField(L("Title"), text: $draft.title)
                }

                Section(L("Details")) {
                    TextField(L("Note"), text: $draft.note, axis: .vertical)
                        .lineLimit(3...8)
                    TextField(L("Source URL (optional)"), text: $draft.sourceURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle(L("Add milestone"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Add"), action: save)
                }
            }
            .alert(L("Couldn’t add milestone"), isPresented: errorPresented) {
                Button(L("OK")) { errorMessage = nil }
            } message: {
                Text(L(errorMessage ?? "Unknown error"))
            }
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func save() {
        do {
            try onSave(draft)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Reminders

struct ReminderDraft {
    var kind = ReminderKind.checkIn
    var date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    var leadDays = 0
    var label = ""

    /// The check-in or deadline event stored in SwiftData.
    var triggerAt: Date { date }

    /// The actual local-notification time shown for confirmation.
    var notificationAt: Date {
        kind == .deadline
            ? Calendar.current.date(byAdding: .day, value: -max(0, leadDays), to: date) ?? date
            : date
    }
}

struct AddReminderSheet: View {
    @EnvironmentObject private var localization: LocalizationCenter
    let defaultLeadDays: Int
    let onSave: (ReminderDraft) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: ReminderDraft
    @State private var errorMessage: String?

    init(defaultLeadDays: Int, onSave: @escaping (ReminderDraft) throws -> Void) {
        self.defaultLeadDays = defaultLeadDays
        self.onSave = onSave
        _draft = State(initialValue: ReminderDraft())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L("Reminder")) {
                    Picker(L("Kind"), selection: $draft.kind) {
                        ForEach(ReminderKind.allCases, id: \.self) { kind in
                            Label(localizedReminderKindLabel(kind), systemImage: kind.symbolName).tag(kind)
                        }
                    }
                    DatePicker(
                        draft.kind == .deadline ? L("Deadline date") : L("Check-in date"),
                        selection: $draft.date,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    Stepper(value: $draft.leadDays, in: 0...365) {
                        Text(draft.leadDays == 1 ? L("Lead time: %lld day", draft.leadDays) : L("Lead time: %lld days", draft.leadDays))
                    }
                    TextField(L("Label"), text: $draft.label, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    Label(
                        L("Notification: %@", orderDetailDateTime(draft.notificationAt)),
                        systemImage: "bell"
                    )
                    Text(L("The selected lead time is subtracted from the event date to calculate the actual notification time."))
                        .heldCaption()
                        .foregroundStyle(HeldColor.secondaryInk)
                    if draft.kind == .deadline {
                        Text(L("Custom deadlines are organizational aids, not payment-protection decisions. Verify current rules with your payment provider; Keyvow does not determine eligibility, file disputes, or guarantee recovery."))
                            .heldCaption()
                            .foregroundStyle(HeldColor.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if draft.notificationAt <= Date() {
                        Text(L("This notification time is in the past. Choose a later date or reduce the lead time."))
                            .heldCaption()
                            .foregroundStyle(HeldColor.danger)
                    }
                }
            }
            .onChange(of: draft.kind) { _, newKind in
                switch newKind {
                case .checkIn:
                    draft.leadDays = 0
                case .deadline:
                    draft.leadDays = min(365, max(0, defaultLeadDays))
                }
            }
            .navigationTitle(L("Add reminder"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Add"), action: save)
                        .disabled(draft.notificationAt <= Date())
                }
            }
            .alert(L("Couldn’t add reminder"), isPresented: errorPresented) {
                Button(L("OK")) { errorMessage = nil }
            } message: {
                Text(L(errorMessage ?? "Unknown error"))
            }
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func save() {
        do {
            try onSave(draft)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Notes and tracking

struct OrderNotesDraft {
    var notes: String
    var trackingNumber: String
    var carrier: String
}

struct EditNotesSheet: View {
    @EnvironmentObject private var localization: LocalizationCenter
    let onSave: (OrderNotesDraft) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: OrderNotesDraft
    @State private var errorMessage: String?

    init(order: HeldOrder, onSave: @escaping (OrderNotesDraft) throws -> Void) {
        self.onSave = onSave
        _draft = State(initialValue: OrderNotesDraft(
            notes: order.notes,
            trackingNumber: order.trackingNumber,
            carrier: order.carrier
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L("Notes")) {
                    TextField(L("Order notes"), text: $draft.notes, axis: .vertical)
                        .lineLimit(6...16)
                }
                Section(L("Tracking")) {
                    TextField(L("Carrier"), text: $draft.carrier)
                        .textInputAutocapitalization(.words)
                    TextField(L("Tracking number"), text: $draft.trackingNumber)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle(L("Notes & tracking"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Save"), action: save)
                }
            }
            .alert(L("Couldn’t save notes"), isPresented: errorPresented) {
                Button(L("OK")) { errorMessage = nil }
            } message: {
                Text(L(errorMessage ?? "Unknown error"))
            }
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func save() {
        do {
            try onSave(draft)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
