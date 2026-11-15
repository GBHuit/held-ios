import SwiftUI
import UIKit

// MARK: - Color

/// Held's asset-independent palette. Every color adapts to the interface style.
enum HeldColor {
    static let background = adaptive(light: 0xF7F5EF, dark: 0x141714)
    static let surface = adaptive(light: 0xFCFAF6, dark: 0x1C211D)
    static let surfaceElevated = adaptive(light: 0xFFFFFF, dark: 0x242A25)

    static let ink = adaptive(light: 0x222822, dark: 0xF3F0E8)
    static let secondaryInk = adaptive(light: 0x62675F, dark: 0xB7BBB1)

    static let accent = adaptive(light: 0x244D40, dark: 0x91B7A5)
    static let accentSoft = adaptive(light: 0xE4ECE5, dark: 0x2C3A32)
    static let amber = adaptive(light: 0xB58A50, dark: 0xD1AD78)
    static let amberSoft = adaptive(light: 0xF1E6D4, dark: 0x3B3226)
    static let terracotta = adaptive(light: 0xA95642, dark: 0xD9937E)

    static let separator = adaptive(light: 0xDCD8CC, dark: 0x3B403A)
    static let success = adaptive(light: 0x35644F, dark: 0x86B69C)
    static let danger = adaptive(light: 0xA5443A, dark: 0xDF8C7E)

    /// Readable label color for content placed on `accent`.
    static let onAccent = adaptive(light: 0xF7F5EF, dark: 0x14231E)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor(dynamicProvider: { traits in
            traits.userInterfaceStyle == .dark ? rgb(dark) : rgb(light)
        }))
    }

    private static func rgb(_ hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Typography

/// Semantic type styles. The serif styles use the native New York design.
enum HeldFont {
    static let display = Font.system(.largeTitle, design: .serif).weight(.semibold)
    static let title = Font.system(.title2, design: .serif).weight(.semibold)
    static let body = Font.body
    static let caption = Font.caption
    static let button = Font.headline.weight(.semibold)
}

private struct HeldDisplayFontModifier: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight

    init(size: CGFloat, relativeTo textStyle: Font.TextStyle, weight: Font.Weight) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
        self.weight = weight
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: .serif))
    }
}

// MARK: - Spacing

enum HeldSpacing {
    static let extraSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 16
    static let large: CGFloat = 24
    static let extraLarge: CGFloat = 32
    static let section: CGFloat = 48
}

// MARK: - View conveniences

extension View {
    /// A custom-size New York display font that scales with Dynamic Type.
    func heldDisplay(
        size: CGFloat = 34,
        weight: Font.Weight = .semibold,
        relativeTo textStyle: Font.TextStyle = .title
    ) -> some View {
        modifier(HeldDisplayFontModifier(size: size, relativeTo: textStyle, weight: weight))
    }

    func heldTitle() -> some View {
        font(HeldFont.title)
    }

    func heldBody() -> some View {
        font(HeldFont.body)
    }

    func heldCaption() -> some View {
        font(HeldFont.caption)
    }

    /// Paints the warm screen canvas, including behind safe areas.
    func heldScreenBackground() -> some View {
        background(HeldColor.background.ignoresSafeArea())
    }

    func heldNavigationTitle(_ title: LocalizedStringKey) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
    }

    func heldNavigationTitle(_ title: String) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
    }

    /// Dismisses the keyboard on a tap without taking over existing gestures.
    func heldKeyboardDismissal() -> some View {
        simultaneousGesture(
            TapGesture().onEnded {
                HeldKeyboard.dismiss()
            }
        )
    }
}

enum HeldKeyboard {
    static func dismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}
