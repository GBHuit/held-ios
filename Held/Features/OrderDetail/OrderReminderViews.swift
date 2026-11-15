import SwiftUI
import UserNotifications

struct OrderRemindersSection: View {
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
                title: "Reminders",
                subtitle: scheduler.authorizationStatusDescription
            ) {
                Button(action: onAdd) {
                    Label("Add reminder", systemImage: "plus")
                }
                .heldButtonStyle(.secondary)
            }

            if scheduler.authorizationStatus == .notDetermined {
                OrderDetailCallout(
                    title: "Allow notifications",
                    message: "Held only asks for notification access after your explicit action. Reminder changes are saved even when system notifications are unavailable.",
                    symbolName: "bell.badge",
                    tone: .info
                )
                Button("Enable notifications", action: onRequestAuthorization)
                    .heldButtonStyle(.secondary)
            } else if scheduler.authorizationStatus == .denied {
                OrderDetailCallout(
                    title: "Notifications are off",
                    message: "Your reminder list remains available here. Enable Held notifications in iOS Settings to receive system alerts.",
                    symbolName: "bell.slash",
                    tone: .warning
                )
            }

            if reminders.isEmpty {
                HeldCard {
                    Text("No reminders yet. Add a check-in or deadline to keep the next step visible.")
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
                     ? "\(reminder.kind.displayLabel) · No lead time"
                     : "\(reminder.kind.displayLabel) · \(reminder.leadDays)-day lead")
                    .heldCaption()
                    .foregroundStyle(HeldColor.secondaryInk)
            }

            Spacer(minLength: HeldSpacing.small)

            Toggle(
                "Reminder enabled",
                isOn: Binding(
                    get: { reminder.enabled },
                    set: { onToggle(reminder, $0) }
                )
            )
            .labelsHidden()
            .accessibilityLabel("Enable \(reminder.label)")
        }
        .padding(HeldSpacing.medium)
    }
}
