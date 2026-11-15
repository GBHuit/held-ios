import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

/// The complete native order detail screen. The parent owns the NavigationStack.
@MainActor
struct OrderDetailView: View {
    let order: HeldOrder

    @Environment(\.modelContext) var modelContext
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var reminderScheduler: ReminderScheduler
    @Query var settings: [AppSettings]

    @State var activeSheet: OrderDetailSheet?
    @State var selectedEvidence: Evidence?
    @State var shareItem: OrderShareItem?
    @State var attachmentStore: AttachmentStore?
    @State var storageError: String?
    @State var errorMessage: String?
    @State var deletionCleanupWarning: String?
    @State var isFileImporterPresented = false
    @State var isPhotoPickerPresented = false
    @State var selectedPhoto: PhotosPickerItem?
    @State var isDeleteOrderConfirmationPresented = false
    @State var isWorking = false

    init(order: HeldOrder) {
        self.order = order
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: HeldSpacing.extraLarge) {
                OrderDetailHeader(order: order)
                OrderStatusSection(
                    order: order,
                    onFulfillmentChange: updateFulfillmentStatus,
                    onResolutionChange: updateResolutionStatus
                )
                OrderEstimateSection(order: order)
                OrderItemsSection(order: order) {
                    activeSheet = .delivery
                }
                OrderTimelineSection(order: order) {
                    activeSheet = .milestone
                }
                OrderRemindersSection(
                    order: order,
                    scheduler: reminderScheduler,
                    onAdd: { activeSheet = .reminder },
                    onToggle: updateReminder,
                    onRequestAuthorization: requestNotificationAuthorization
                )
                OrderEvidenceSection(
                    order: order,
                    attachmentStore: attachmentStore,
                    storageError: storageError,
                    onSelect: { selectedEvidence = $0 },
                    onAddDetails: { activeSheet = .evidence(EvidenceDraft()) },
                    onImportFile: { isFileImporterPresented = true },
                    onImportPhoto: { isPhotoPickerPresented = true },
                    onScanText: { activeSheet = .liveText }
                )
                OrderNotesSection(order: order) {
                    activeSheet = .notes
                }
                OrderDangerSection {
                    isDeleteOrderConfirmationPresented = true
                }
            }
            .padding(HeldSpacing.large)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .heldScreenBackground()
        .navigationTitle(order.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(item: $activeSheet, content: sheetContent)
        .sheet(item: $selectedEvidence) { evidence in
            EvidenceDetailSheet(
                evidence: evidence,
                attachmentStore: attachmentStore,
                onDelete: deleteEvidence
            )
        }
        .sheet(item: $shareItem) { item in
            OrderShareSheet(item: item)
                .ignoresSafeArea()
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false,
            onCompletion: importSelectedFile
        )
        .photosPicker(
            isPresented: $isPhotoPickerPresented,
            selection: $selectedPhoto,
            matching: .images
        )
        .onChange(of: selectedPhoto) { _, newValue in
            if let newValue { importSelectedPhoto(newValue) }
        }
        .task(perform: prepareAttachmentStore)
        .heldLoadingOverlay(isPresented: isWorking, title: "Working…")
        .alert("Order action needs attention", isPresented: errorPresented) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .alert("Delete this order?", isPresented: $isDeleteOrderConfirmationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Delete order", role: .destructive, action: deleteOrder)
        } message: {
            Text("This permanently deletes the order, its reminders, milestones, evidence metadata, and imported attachments. This cannot be undone.")
        }
        .alert("Order deleted", isPresented: deletionWarningPresented) {
            Button("Done") { dismiss() }
        } message: {
            Text(deletionCleanupWarning ?? "")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Edit") { activeSheet = .edit }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                ForEach(OrderExportKind.allCases) { kind in
                    Button {
                        activeSheet = .export(kind)
                    } label: {
                        Label(kind.title, systemImage: kind.symbolName)
                    }
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .accessibilityLabel("Export order")
        }
    }

    @ViewBuilder
    private func sheetContent(for sheet: OrderDetailSheet) -> some View {
        switch sheet {
        case .edit:
            EditOrderSheet(order: order, onSave: applyOrderEdit)
        case .delivery:
            UpdateDeliverySheet(items: order.items, onSave: applyDeliveryUpdate)
        case .milestone:
            AddMilestoneSheet(onSave: addMilestone)
        case .reminder:
            AddReminderSheet(
                defaultLeadDays: settings.first?.leadDays ?? 0,
                onSave: addReminder
            )
        case .notes:
            EditNotesSheet(order: order, onSave: applyNotesUpdate)
        case .evidence(let draft):
            EvidenceEntrySheet(
                draft: draft,
                attachmentStore: attachmentStore,
                onSave: saveEvidence,
                onCancel: cancelEvidenceImport
            )
        case .liveText:
            OrderLiveTextSheet { text in
                var draft = EvidenceDraft()
                draft.kind = .communication
                draft.title = "Scanned text"
                draft.source = "Live text scan"
                draft.note = text
                activeSheet = .evidence(draft)
            }
        case .export(let kind):
            OrderExportPreviewSheet(order: order, kind: kind) {
                prepareExport(kind)
            }
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private var deletionWarningPresented: Binding<Bool> {
        Binding(
            get: { deletionCleanupWarning != nil },
            set: { if !$0 { deletionCleanupWarning = nil } }
        )
    }
}
