import SwiftUI
import UserNotifications

struct OrderRemindersSection: View {
    @EnvironmentObject private var localization: LocalizationCenter
    let order: HeldOrder
    let scheduler: ReminderScheduler
    let onAdd: () -> Void
    let onToggle: (HeldReminder, Bool) -> Void
    let onRequestAuthorization: () -> Void

    private var reminders: [HeldReminder] {
        order.reminders.sorted {
            if $0.triggerAt == $1.triggerAt { return $0.id < $1.id }
            return $0.triggerAt < $1.triggerAt
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HeldSpacing.medium) {
            HeldSectionHeader(
                title: L("Reminders"),
                subtitle: L(scheduler.authorizationStatusDescription)
            ) {
                Button(action: onAdd) {
                    Label(L("Add reminder"), systemImage: "plus")
                }
                .heldButtonStyle(.secondary)
            }

            if scheduler.authorizationStatus == .notDetermined {
                OrderDetailCallout(
                    title: L("Allow notifications"),
                    message: L("Keyvow only asks for notification access after your explicit action. Reminder changes are saved even when system notifications are unavailable."),
                    symbolName: "bell.badge",
                    tone: .info
                )
                Button(L("Enable notifications"), action: onRequestAuthorization)
                    .heldButtonStyle(.secondary)
            } else if scheduler.authorizationStatus == .denied {
                OrderDetailCallout(
                    title: L("Notifications are off"),
                    message: L("Your reminder list remains available here. Enable Keyvow notifications in iOS Settings to receive system alerts."),
                    symbolName: "bell.slash",
                    tone: .warning
                )
            }

            if reminders.isEmpty {
                HeldCard {
                    Text(L("No reminders yet. Add a check-in or deadline to keep the next step visible."))
                        .foregroundStyle(HeldColor.secondaryInk)
                }
            } else {
                HeldCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(reminders.enumerated()), id: \.element.id) { index, reminder in
                            ReminderRow(reminder: reminder, onToggle: onToggle)
                            if index < reminders.count - 1 {
                                Divider()
                                    .overlay(HeldColor.separator)
                                    .padding(.leading, 52)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct ReminderRow: View {
    @EnvironmentObject private var localization: LocalizationCenter
    let reminder: HeldReminder
    let onToggle: (HeldReminder, Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: HeldSpacing.medium) {
            Image(systemName: reminder.kind.symbolName)
                .font(.title3)
                .foregroundStyle(HeldColor.accent)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: HeldSpacing.extraSmall) {
                Text(reminder.label)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(orderDetailDateTime(reminder.triggerAt))
                    .heldCaption()
                    .foregroundStyle(HeldColor.secondaryInk)
                Text(reminder.leadDays == 0
                     ? L("%@ · No lead time", localizedReminderKindLabel(reminder.kind))
                     : L("%1$@ · %2$lld-day lead", localizedReminderKindLabel(reminder.kind), reminder.leadDays))
                    .heldCaption()
                    .foregroundStyle(HeldColor.secondaryInk)
            }

            Spacer(minLength: HeldSpacing.small)

            Toggle(
                L("Reminder enabled"),
                isOn: Binding(
                    get: { reminder.enabled },
                    set: { onToggle(reminder, $0) }
                )
            )
            .labelsHidden()
            .accessibilityLabel(L("Enable %@", reminder.label))
        }
        .padding(HeldSpacing.medium)
    }
}
