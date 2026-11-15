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
    var estimateEnd: Date?
    var nextCheckAt: Date?
    var estimateRevisionNote: String
}

struct EditOrderSheet: View {
    let order: HeldOrder
    let onSave: (OrderEditDraft) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: OrderEditDraft
    @State private var hasEstimate: Bool
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
            estimateEnd: order.estimateEnd,
            nextCheckAt: order.nextCheckAt,
            estimateRevisionNote: ""
        )
        _draft = State(initialValue: draft)
        _hasEstimate = State(initialValue: order.estimateEnd != nil)
        _hasNextCheck = State(initialValue: order.nextCheckAt != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Order") {
                    TextField("Title", text: $draft.title)
                        .textInputAutocapitalization(.words)
                    TextField("Vendor", text: $draft.vendor)
                        .textInputAutocapitalization(.words)
                    TextField("Order number", text: $draft.orderNumber)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    DatePicker("Ordered at", selection: $draft.orderedAt)
                }

                Section("Amount & payment") {
                    HStack {
                        TextField("Amount", text: $draft.amountText)
                            .keyboardType(.decimalPad)
                            .accessibilityLabel("Order amount")
                        Picker("Currency", selection: $draft.currencyCode) {
                            ForEach(CurrencyCode.allCases, id: \.self) { currency in
                                Text(currency.displayLabel).tag(currency)
                            }
                        }
                        .labelsHidden()
                        .accessibilityLabel("Currency")
                    }
                    TextField("Payment method", text: $draft.paymentMethod)
                }

                Section("Source") {
                    TextField("https://example.com/order", text: $draft.sourceURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    OrderDetailCallout(
                        title: "Original estimate is immutable",
                        message: order.estimateText.isEmpty
                            ? "No original estimate text is recorded. A date revision creates a milestone and leaves this field untouched."
                            : order.estimateText,
                        symbolName: "lock.fill",
                        tone: .warning
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)

                    Toggle("Current estimate end", isOn: $hasEstimate.animation())
                    if hasEstimate {
                        DatePicker(
                            "Estimate end",
                            selection: estimateBinding,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        TextField("Revision note (optional)", text: $draft.estimateRevisionNote, axis: .vertical)
                            .lineLimit(2...5)
                        Text("Saving a changed estimate date adds a timeline milestone. Original estimate text and original evidence are never overwritten.")
                            .heldCaption()
                            .foregroundStyle(HeldColor.secondaryInk)
                    }
                } header: {
                    Text("Current estimate")
                }

                Section("Next check") {
                    Toggle("Schedule next check", isOn: $hasNextCheck.animation())
                    if hasNextCheck {
                        DatePicker(
                            "Next check",
                            selection: nextCheckBinding,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                }
            }
            .navigationTitle("Edit order")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
            .alert("Couldn’t save order", isPresented: errorPresented) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }

    private var estimateBinding: Binding<Date> {
        Binding(
            get: { draft.estimateEnd ?? Date() },
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
        draft.estimateEnd = hasEstimate ? (draft.estimateEnd ?? Date()) : nil
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
                    Text("Delivered is derived only when every noncancelled item has its full quantity delivered. Any shipped or partially delivered item otherwise keeps the order partially shipped.")
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
                            Text("\(draft.deliveredQuantity) of \(draft.quantity) delivered")
                                .font(.headline.monospacedDigit())
                        }
                        .accessibilityLabel("Delivered quantity for \(draft.name)")
                        Picker("Item status", selection: statusBinding(for: $draft)) {
                            ForEach(ItemStatus.allCases, id: \.self) { status in
                                Text(status.displayLabel).tag(status)
                            }
                        }
                    } header: {
                        Text(draft.name)
                    }
                }
            }
            .navigationTitle("Update delivery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
            .alert("Couldn’t update delivery", isPresented: errorPresented) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Unknown error")
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
    let onSave: (MilestoneDraft) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = MilestoneDraft()
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Milestone") {
                    Picker("Kind", selection: $draft.kind) {
                        ForEach(MilestoneKind.allCases, id: \.self) { kind in
                            Label(kind.displayLabel, systemImage: kind.symbolName).tag(kind)
                        }
                    }
                    DatePicker(
                        "Date",
                        selection: $draft.occurredAt,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    TextField("Title", text: $draft.title)
                }

                Section("Details") {
                    TextField("Note", text: $draft.note, axis: .vertical)
                        .lineLimit(3...8)
                    TextField("Source URL (optional)", text: $draft.sourceURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Add milestone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: save)
                }
            }
            .alert("Couldn’t add milestone", isPresented: errorPresented) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Unknown error")
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
                Section("Reminder") {
                    Picker("Kind", selection: $draft.kind) {
                        ForEach(ReminderKind.allCases, id: \.self) { kind in
                            Label(kind.displayLabel, systemImage: kind.symbolName).tag(kind)
                        }
                    }
                    DatePicker(
                        draft.kind == .deadline ? "Deadline date" : "Check-in date",
                        selection: $draft.date,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    Stepper(value: $draft.leadDays, in: 0...365) {
                        Text("Lead time: \(draft.leadDays) \(draft.leadDays == 1 ? "day" : "days")")
                    }
                    TextField("Label", text: $draft.label, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    Label(
                        "Notification: \(orderDetailDateTime(draft.notificationAt))",
                        systemImage: "bell"
                    )
                    Text("The selected lead time is subtracted from the event date to calculate the actual notification time.")
                        .heldCaption()
                        .foregroundStyle(HeldColor.secondaryInk)
                    if draft.notificationAt <= Date() {
                        Text("This notification time is in the past. Choose a later date or reduce the lead time.")
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
            .navigationTitle("Add reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: save)
                        .disabled(draft.notificationAt <= Date())
                }
            }
            .alert("Couldn’t add reminder", isPresented: errorPresented) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Unknown error")
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
                Section("Notes") {
                    TextField("Order notes", text: $draft.notes, axis: .vertical)
                        .lineLimit(6...16)
                }
                Section("Tracking") {
                    TextField("Carrier", text: $draft.carrier)
                        .textInputAutocapitalization(.words)
                    TextField("Tracking number", text: $draft.trackingNumber)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Notes & tracking")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
            .alert("Couldn’t save notes", isPresented: errorPresented) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Unknown error")
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
