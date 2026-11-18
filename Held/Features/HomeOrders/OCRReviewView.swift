import SwiftUI

struct OCRConfirmedSuggestions {
    var productTitle: String?
    var vendor: String?
    var estimatedDeliveryText: String?
    var orderNumber: String?
    var orderDate: Date?
    var amount: Decimal?
    var currency: CurrencyCode?
}

struct OCRReviewView: View {
    @EnvironmentObject private var localization: LocalizationCenter
    let result: OCRResult
    let canKeepReceipt: Bool
    let onApply: (OCRConfirmedSuggestions) -> Void
    let onCancel: () -> Void

    @State private var selectedProductTitle: Int?
    @State private var selectedVendor: Int?
    @State private var selectedDeliveryText: Int?
    @State private var selectedOrderNumber: Int?
    @State private var selectedDate: Int?
    @State private var selectedTotal: Int?

    private var hasCandidates: Bool {
        !result.candidates.productTitles.isEmpty ||
        !result.candidates.vendors.isEmpty ||
        !result.candidates.estimatedDeliveryTexts.isEmpty ||
        !result.candidates.orderNumbers.isEmpty ||
        !result.candidates.dates.isEmpty ||
        !result.candidates.totals.isEmpty
    }

    private var hasSelection: Bool {
        selectedProductTitle != nil || selectedVendor != nil ||
        selectedDeliveryText != nil || selectedOrderNumber != nil ||
        selectedDate != nil || selectedTotal != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HeldSpacing.large) {
                    VStack(alignment: .leading, spacing: HeldSpacing.small) {
                        Text(L("OCR suggestions need your confirmation"))
                            .heldTitle()
                            .foregroundStyle(HeldColor.ink)
                            .accessibilityAddTraits(.isHeader)
                        Text(L(result.limitations))
                            .heldBody()
                            .foregroundStyle(HeldColor.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !hasCandidates {
                        HomeOrdersMessage(
                            title: L("No fields to apply"),
                            message: L("The image did not yield a supported order field. You can keep the reviewed image as receipt evidence, or return to the form and enter everything manually."),
                            systemImage: "text.viewfinder"
                        )
                    } else {
                        textCandidateSection(
                            title: L("Product title"),
                            subtitle: L("Choose only a recognized product or item name; check its source line."),
                            candidates: result.candidates.productTitles,
                            selection: $selectedProductTitle
                        )
                        textCandidateSection(
                            title: L("Vendor"),
                            subtitle: L("Seller extraction can confuse stores, carriers, and marketplaces."),
                            candidates: result.candidates.vendors,
                            selection: $selectedVendor
                        )
                        textCandidateSection(
                            title: L("Estimated delivery text"),
                            subtitle: L("This preserves the recognized wording; it does not calculate a delivery date."),
                            candidates: result.candidates.estimatedDeliveryTexts,
                            selection: $selectedDeliveryText
                        )
                        textCandidateSection(
                            title: L("Order number"),
                            subtitle: L("Choose at most one recognized value."),
                            candidates: result.candidates.orderNumbers,
                            selection: $selectedOrderNumber
                        )
                        dateCandidates
                        totalCandidates
                    }

                    if !result.fullText.isEmpty {
                        DisclosureGroup(L("Recognized text")) {
                            Text(result.fullText)
                                .heldCaption()
                                .foregroundStyle(HeldColor.secondaryInk)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, HeldSpacing.small)
                        }
                        .tint(HeldColor.accent)
                        .foregroundStyle(HeldColor.ink)
                    }
                }
                .padding(HeldSpacing.medium)
            }
            .heldScreenBackground()
            .navigationTitle(L("Review OCR"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Not now"), action: onCancel)
                        .frame(minWidth: 44, minHeight: 44)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: HeldSpacing.small) {
                    if hasCandidates {
                        Button(L("Apply selected suggestions")) {
                            applySelections()
                        }
                        .heldButtonStyle()
                        .disabled(!hasSelection)
                    }
                    if canKeepReceipt {
                        Button(L("Keep receipt without OCR changes")) {
                            onApply(OCRConfirmedSuggestions())
                        }
                        .heldButtonStyle(.secondary)
                    }
                    Button(L("Continue manually"), action: onCancel)
                        .heldButtonStyle(.quiet)
                }
                .padding(.horizontal, HeldSpacing.medium)
                .padding(.vertical, HeldSpacing.small)
                .background(HeldColor.background.ignoresSafeArea(edges: .bottom))
            }
            .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private func textCandidateSection(
        title: String,
        subtitle: String,
        candidates: [OCRTextCandidate],
        selection: Binding<Int?>
    ) -> some View {
        if !candidates.isEmpty {
            candidateSection(title: title, subtitle: subtitle) {
                ForEach(Array(candidates.enumerated()), id: \.offset) { index, candidate in
                    OCRSelectionCard(
                        isSelected: selection.wrappedValue == index,
                        action: { selection.wrappedValue = selection.wrappedValue == index ? nil : index }
                    ) {
                        OCRCandidateText(
                            value: candidate.value,
                            sourceText: candidate.sourceText,
                            confidence: candidate.confidence
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var dateCandidates: some View {
        if !result.candidates.dates.isEmpty {
            candidateSection(title: L("Order date"), subtitle: L("Dates can refer to delivery or payment, so check the source line.")) {
                ForEach(Array(result.candidates.dates.enumerated()), id: \.offset) { index, candidate in
                    OCRSelectionCard(
                        isSelected: selectedDate == index,
                        action: { selectedDate = selectedDate == index ? nil : index }
                    ) {
                        OCRCandidateText(
                            value: localization.date(candidate.value),
                            sourceText: candidate.sourceText,
                            confidence: candidate.confidence
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var totalCandidates: some View {
        if !result.candidates.totals.isEmpty {
            candidateSection(title: L("Order total"), subtitle: L("Unsupported or uncertain currency codes leave your selected currency unchanged.")) {
                ForEach(Array(result.candidates.totals.enumerated()), id: \.offset) { index, candidate in
                    OCRSelectionCard(
                        isSelected: selectedTotal == index,
                        action: { selectedTotal = selectedTotal == index ? nil : index }
                    ) {
                        OCRCandidateText(
                            value: amountDescription(candidate),
                            sourceText: candidate.sourceText,
                            confidence: candidate.confidence
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func candidateSection<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: HeldSpacing.medium) {
            VStack(alignment: .leading, spacing: HeldSpacing.extraSmall) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(HeldColor.ink)
                Text(subtitle)
                    .heldCaption()
                    .foregroundStyle(HeldColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func amountDescription(_ candidate: OCRAmountCandidate) -> String {
        let formatter = NumberFormatter()
        formatter.locale = localization.locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        let amount = formatter.string(from: NSDecimalNumber(decimal: candidate.value))
            ?? NSDecimalNumber(decimal: candidate.value).stringValue
        if let currencyCode = candidate.currencyCode {
            return L("%1$@ %2$@", amount, currencyCode)
        }
        return L("%@ — currency not recognized", amount)
    }

    private func applySelections() {
        var suggestions = OCRConfirmedSuggestions()

        if let selectedProductTitle,
           result.candidates.productTitles.indices.contains(selectedProductTitle) {
            suggestions.productTitle = result.candidates.productTitles[selectedProductTitle].value
        }
        if let selectedVendor,
           result.candidates.vendors.indices.contains(selectedVendor) {
            suggestions.vendor = result.candidates.vendors[selectedVendor].value
        }
        if let selectedDeliveryText,
           result.candidates.estimatedDeliveryTexts.indices.contains(selectedDeliveryText) {
            suggestions.estimatedDeliveryText = result.candidates.estimatedDeliveryTexts[selectedDeliveryText].value
        }
        if let selectedOrderNumber,
           result.candidates.orderNumbers.indices.contains(selectedOrderNumber) {
            suggestions.orderNumber = result.candidates.orderNumbers[selectedOrderNumber].value
        }
        if let selectedDate,
           result.candidates.dates.indices.contains(selectedDate) {
            suggestions.orderDate = result.candidates.dates[selectedDate].value
        }
        if let selectedTotal,
           result.candidates.totals.indices.contains(selectedTotal) {
            let candidate = result.candidates.totals[selectedTotal]
            suggestions.amount = candidate.value
            suggestions.currency = candidate.currencyCode.flatMap { CurrencyCode(rawValue: $0) }
        }

        onApply(suggestions)
    }
}

private struct OCRCandidateText: View {
    @EnvironmentObject private var localization: LocalizationCenter
    let value: String
    let sourceText: String
    let confidence: Double

    var body: some View {
        VStack(alignment: .leading, spacing: HeldSpacing.extraSmall) {
            Text(value)
                .font(.headline)
                .foregroundStyle(HeldColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(L("Seen in: %@", sourceText))
                .heldCaption()
                .foregroundStyle(HeldColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Text(L("Extraction confidence %@ — a hint, not certainty", localization.percentage(confidence)))
                .font(.caption2)
                .foregroundStyle(HeldColor.secondaryInk)
        }
    }
}

private struct OCRSelectionCard<Content: View>: View {
    @EnvironmentObject private var localization: LocalizationCenter
    let isSelected: Bool
    let action: () -> Void
    private let content: Content

    init(
        isSelected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.isSelected = isSelected
        self.action = action
        self.content = content()
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: HeldSpacing.medium) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? HeldColor.accent : HeldColor.secondaryInk)
                    .padding(.top, 1)
                    .accessibilityHidden(true)
                content
                Spacer(minLength: 0)
            }
            .padding(HeldSpacing.medium)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(
                isSelected ? HeldColor.accentSoft : HeldColor.surface,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? HeldColor.accent : HeldColor.separator, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isSelected ? L("Double-tap to remove this suggestion") : L("Double-tap to choose this suggestion"))
    }
}
