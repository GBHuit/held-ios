import SwiftUI

struct OCRConfirmedSuggestions {
    var orderNumber: String?
    var orderDate: Date?
    var amount: Decimal?
    var currency: CurrencyCode?
}

struct OCRReviewView: View {
    let result: OCRResult
    let onApply: (OCRConfirmedSuggestions) -> Void
    let onCancel: () -> Void

    @State private var selectedOrderNumber: Int?
    @State private var selectedDate: Int?
    @State private var selectedTotal: Int?

    private var hasCandidates: Bool {
        !result.candidates.orderNumbers.isEmpty ||
        !result.candidates.dates.isEmpty ||
        !result.candidates.totals.isEmpty
    }

    private var hasSelection: Bool {
        selectedOrderNumber != nil || selectedDate != nil || selectedTotal != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HeldSpacing.large) {
                    VStack(alignment: .leading, spacing: HeldSpacing.small) {
                        Text("OCR suggestions need your confirmation")
                            .heldTitle()
                            .foregroundStyle(HeldColor.ink)
                            .accessibilityAddTraits(.isHeader)
                        Text(result.limitations)
                            .heldBody()
                            .foregroundStyle(HeldColor.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !hasCandidates {
                        HomeOrdersMessage(
                            title: "No fields to apply",
                            message: "The image did not yield an order number, date, or total. You can return to the form and enter everything manually.",
                            systemImage: "text.viewfinder"
                        )
                    } else {
                        orderNumberCandidates
                        dateCandidates
                        totalCandidates
                    }

                    if !result.fullText.isEmpty {
                        DisclosureGroup("Recognized text") {
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
            .navigationTitle("Review OCR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now", action: onCancel)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: HeldSpacing.small) {
                    if hasCandidates {
                        Button("Apply selected suggestions") {
                            applySelections()
                        }
                        .heldButtonStyle()
                        .disabled(!hasSelection)
                    }
                    Button("Continue manually", action: onCancel)
                        .heldButtonStyle(.secondary)
                }
                .padding(.horizontal, HeldSpacing.medium)
                .padding(.vertical, HeldSpacing.small)
                .background(HeldColor.background.ignoresSafeArea(edges: .bottom))
            }
            .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private var orderNumberCandidates: some View {
        if !result.candidates.orderNumbers.isEmpty {
            candidateSection(title: "Order number", subtitle: "Choose at most one recognized value.") {
                ForEach(Array(result.candidates.orderNumbers.enumerated()), id: \.offset) { index, candidate in
                    OCRSelectionCard(
                        isSelected: selectedOrderNumber == index,
                        action: { selectedOrderNumber = selectedOrderNumber == index ? nil : index }
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
            candidateSection(title: "Order date", subtitle: "Dates can refer to delivery or payment, so check the source line.") {
                ForEach(Array(result.candidates.dates.enumerated()), id: \.offset) { index, candidate in
                    OCRSelectionCard(
                        isSelected: selectedDate == index,
                        action: { selectedDate = selectedDate == index ? nil : index }
                    ) {
                        OCRCandidateText(
                            value: formatDate(candidate.value),
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
            candidateSection(title: "Order total", subtitle: "Unsupported or uncertain currency codes leave your selected currency unchanged.") {
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
        let amount = NSDecimalNumber(decimal: candidate.value).stringValue
        if let currencyCode = candidate.currencyCode {
            return "\(amount) \(currencyCode)"
        }
        return "\(amount) — currency not recognized"
    }

    private func applySelections() {
        var suggestions = OCRConfirmedSuggestions()

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
    let value: String
    let sourceText: String
    let confidence: Double

    var body: some View {
        VStack(alignment: .leading, spacing: HeldSpacing.extraSmall) {
            Text(value)
                .font(.headline)
                .foregroundStyle(HeldColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Seen in: \(sourceText)")
                .heldCaption()
                .foregroundStyle(HeldColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Text("Extraction confidence \(Int((confidence * 100).rounded()))% — a hint, not certainty")
                .font(.caption2)
                .foregroundStyle(HeldColor.secondaryInk)
        }
    }
}

private struct OCRSelectionCard<Content: View>: View {
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
            .frame(maxWidth: .infinity, alignment: .leading)
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
        .accessibilityHint(isSelected ? "Double-tap to remove this suggestion" : "Double-tap to choose this suggestion")
    }
}
