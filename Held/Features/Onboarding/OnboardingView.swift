import SwiftUI

/// First-run welcome flow. Two short pages: what Keyvow keeps together, and
/// how to add an order from the share sheet. Shown once; skippable.
struct OnboardingView: View {
    var onFinish: () -> Void

    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            HeldColor.background.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                TabView(selection: $page) {
                    welcomePage.tag(0)
                    sharePage.tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                bottomBar
            }
        }
    }

    private var topBar: some View {
        HStack {
            Text(L("Keyvow"))
                .heldDisplay(size: 20)
                .foregroundStyle(HeldColor.accent)
            Spacer()
            Button {
                onFinish()
            } label: {
                Text(L("Skip"))
                    .heldCaption()
                    .foregroundStyle(HeldColor.secondaryInk)
            }
        }
        .padding(.horizontal, HeldSpacing.medium)
        .padding(.top, HeldSpacing.medium)
    }

    private var welcomePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HeldSpacing.large) {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(HeldColor.amber)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: HeldSpacing.small) {
                    Text(L("Give every promise a place"))
                        .heldDisplay(size: 30)
                        .foregroundStyle(HeldColor.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(L("Keep the original estimate, the progress, the evidence, and the next check-in in one place."))
                        .heldBody()
                        .foregroundStyle(HeldColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: HeldSpacing.medium) {
                    featureRow(
                        icon: "shippingbox",
                        title: L("Track every order"),
                        detail: L("Estimates, progress, and milestones stay together.")
                    )
                    featureRow(
                        icon: "doc.text.magnifyingglass",
                        title: L("Keep the evidence"),
                        detail: L("Receipts, screenshots, and scanned text attach to the order.")
                    )
                    featureRow(
                        icon: "bell.badge",
                        title: L("Never miss a check-in"),
                        detail: L("Reminders follow each order's own schedule.")
                    )
                }
            }
            .padding(.horizontal, HeldSpacing.medium)
            .padding(.top, HeldSpacing.large)
            .padding(.bottom, HeldSpacing.medium)
        }
    }

    private var sharePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HeldSpacing.large) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(HeldColor.amber)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: HeldSpacing.small) {
                    Text(L("Add orders without typing"))
                        .heldDisplay(size: 30)
                        .foregroundStyle(HeldColor.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(L("Share a receipt or order screenshot from any app. Keyvow reads it and starts a new order."))
                        .heldBody()
                        .foregroundStyle(HeldColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: HeldSpacing.medium) {
                    stepRow(number: 1, text: L("Take or find a screenshot"))
                    stepRow(number: 2, text: L("Tap Share and choose Keyvow"))
                    stepRow(number: 3, text: L("Review the pre-filled order"))
                }
            }
            .padding(.horizontal, HeldSpacing.medium)
            .padding(.top, HeldSpacing.large)
            .padding(.bottom, HeldSpacing.medium)
        }
    }

    private var bottomBar: some View {
        VStack(spacing: HeldSpacing.medium) {
            HStack(spacing: HeldSpacing.extraSmall) {
                ForEach(0..<2, id: \.self) { index in
                    Circle()
                        .fill(index == page ? HeldColor.accent : HeldColor.separator)
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                }
            }

            Button {
                if page == 0 {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                        page = 1
                    }
                } else {
                    onFinish()
                }
            } label: {
                Text(page == 0 ? L("Continue") : L("Get started"))
                    .frame(maxWidth: .infinity)
            }
            .heldButtonStyle()
        }
        .padding(.horizontal, HeldSpacing.medium)
        .padding(.bottom, HeldSpacing.large)
    }

    private func featureRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: HeldSpacing.medium) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(HeldColor.accent)
                .frame(width: 26)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: HeldSpacing.extraSmall) {
                Text(title)
                    .heldTitle()
                    .foregroundStyle(HeldColor.ink)
                Text(detail)
                    .heldBody()
                    .foregroundStyle(HeldColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func stepRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: HeldSpacing.medium) {
            Text("\(number)")
                .heldTitle()
                .foregroundStyle(HeldColor.onAccent)
                .frame(width: 26, height: 26)
                .background(Circle().fill(HeldColor.accent))
                .accessibilityHidden(true)

            Text(text)
                .heldBody()
                .foregroundStyle(HeldColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }
}
