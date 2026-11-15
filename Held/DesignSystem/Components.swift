import SwiftUI

// MARK: - Buttons

enum HeldButtonVariant {
    case primary
    case secondary
    case quiet
}

struct HeldButtonStyle: ButtonStyle {
    private let variant: HeldButtonVariant

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ variant: HeldButtonVariant = .primary) {
        self.variant = variant
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(HeldFont.button)
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, variant == .quiet ? 12 : 20)
            .padding(.vertical, 10)
            .frame(minWidth: 44, minHeight: 44)
            .background(
                backgroundColor(isPressed: configuration.isPressed),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                if variant == .secondary {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(HeldColor.accent.opacity(0.45), lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        variant == .primary ? HeldColor.onAccent : HeldColor.accent
    }

    private var cornerRadius: CGFloat {
        variant == .quiet ? 8 : 10
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        switch variant {
        case .primary:
            return HeldColor.accent.opacity(isPressed ? 0.82 : 1)
        case .secondary:
            return isPressed ? HeldColor.accentSoft : .clear
        case .quiet:
            return isPressed ? HeldColor.accentSoft.opacity(0.75) : .clear
        }
    }
}

extension View {
    func heldButtonStyle(_ variant: HeldButtonVariant = .primary) -> some View {
        buttonStyle(HeldButtonStyle(variant))
    }
}

// MARK: - Badges

enum BadgeTone {
    case neutral
    case success
    case warning
    case danger
    case info
}

struct HeldBadge: View {
    private let text: String
    private let tone: BadgeTone

    init(text: String, tone: BadgeTone = .neutral) {
        self.text = text
        self.tone = tone
    }

    var body: some View {
        Text(text)
            .font(HeldFont.caption.weight(.medium))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .frame(minHeight: 24)
            .background(backgroundColor, in: Capsule())
    }

    private var foregroundColor: Color {
        switch tone {
        case .neutral:
            return HeldColor.secondaryInk
        case .success, .info:
            return HeldColor.accent
        case .warning:
            // Ink preserves readability against the muted amber wash.
            return HeldColor.ink
        case .danger:
            return HeldColor.terracotta
        }
    }

    private var backgroundColor: Color {
        switch tone {
        case .neutral:
            return HeldColor.separator.opacity(0.35)
        case .success, .info:
            return HeldColor.accentSoft
        case .warning:
            return HeldColor.amberSoft
        case .danger:
            return HeldColor.terracotta.opacity(0.12)
        }
    }
}

// MARK: - Section headers

struct HeldSectionHeader<Trailing: View>: View {
    private let title: String
    private let subtitle: String?
    private let trailing: Trailing

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: HeldSpacing.medium) {
            VStack(alignment: .leading, spacing: HeldSpacing.extraSmall) {
                Text(title)
                    .heldTitle()
                    .foregroundStyle(HeldColor.ink)

                if let subtitle {
                    Text(subtitle)
                        .heldCaption()
                        .foregroundStyle(HeldColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Spacer(minLength: HeldSpacing.medium)
            trailing
        }
    }
}

extension HeldSectionHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) {
            EmptyView()
        }
    }
}

// MARK: - Cards

struct HeldCard<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    init(
        padding: CGFloat = HeldSpacing.large,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                HeldColor.surface,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(HeldColor.separator, lineWidth: 0.75)
            }
    }
}

// MARK: - Empty states

struct HeldEmptyView: View {
    private let icon: String
    private let title: String
    private let message: String
    private let buttonTitle: String?
    private let action: (() -> Void)?

    init(
        icon: String,
        title: String,
        message: String,
        buttonTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.buttonTitle = buttonTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: HeldSpacing.medium) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(HeldColor.amber)
                .accessibilityHidden(true)

            VStack(spacing: HeldSpacing.small) {
                Text(title)
                    .heldDisplay(size: 26)
                    .foregroundStyle(HeldColor.ink)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text(message)
                    .heldBody()
                    .foregroundStyle(HeldColor.secondaryInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let buttonTitle, let action {
                Button(buttonTitle, action: action)
                    .heldButtonStyle(.secondary)
                    .padding(.top, HeldSpacing.small)
            }
        }
        .frame(maxWidth: 360)
        .padding(HeldSpacing.extraLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Progress

struct HeldProgressView: View {
    private let value: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(value: Double) {
        self.value = value
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(HeldColor.separator.opacity(0.65))

                Capsule()
                    .fill(HeldColor.accent)
                    .frame(width: proxy.size.width * clampedValue)
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: clampedValue)
        }
        .frame(height: 4)
        .accessibilityRepresentation {
            ProgressView(value: clampedValue)
                .accessibilityLabel(Text("Progress"))
        }
    }

    private var clampedValue: Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

// MARK: - Loading

struct HeldLoadingOverlay: View {
    private let title: LocalizedStringKey

    init(_ title: LocalizedStringKey = "Loading…") {
        self.title = title
    }

    var body: some View {
        ZStack {
            HeldColor.background
                .opacity(0.92)
                .ignoresSafeArea()

            VStack(spacing: HeldSpacing.medium) {
                ProgressView()
                    .controlSize(.large)
                    .tint(HeldColor.accent)

                Text(title)
                    .heldBody()
                    .foregroundStyle(HeldColor.secondaryInk)
                    .multilineTextAlignment(.center)
            }
            .padding(HeldSpacing.large)
            .background(
                HeldColor.surfaceElevated,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(HeldColor.separator, lineWidth: 0.75)
            }
            .padding(HeldSpacing.extraLarge)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)
        }
        .accessibilityAddTraits(.isModal)
    }
}

extension View {
    @ViewBuilder
    func heldLoadingOverlay(
        isPresented: Bool,
        title: LocalizedStringKey = "Loading…"
    ) -> some View {
        if isPresented {
            overlay {
                HeldLoadingOverlay(title)
            }
        } else {
            self
        }
    }
}
