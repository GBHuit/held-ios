import Foundation
import Vision
import CoreGraphics
import ImageIO

struct OCRRecognizedLine: Equatable {
    let text: String
    /// Vision's confidence for the recognized text, not for a parsed field.
    let confidence: Double
}

struct OCRTextCandidate: Equatable {
    let value: String
    let sourceText: String
    /// Heuristic extraction confidence. It must not be treated as certainty.
    let confidence: Double
}

struct OCRDateCandidate: Equatable {
    let value: Date
    let sourceText: String
    let confidence: Double
}

struct OCRAmountCandidate: Equatable {
    /// Decimal is deliberately used instead of converting to a currency's minor
    /// units before the user has confirmed the currency and amount.
    let value: Decimal
    let currencyCode: String?
    let sourceText: String
    let confidence: Double
}

struct OCRExtractedCandidates: Equatable {
    let productTitles: [OCRTextCandidate]
    let vendors: [OCRTextCandidate]
    let estimatedDeliveryTexts: [OCRTextCandidate]
    let orderNumbers: [OCRTextCandidate]
    let dates: [OCRDateCandidate]
    let totals: [OCRAmountCandidate]
}

struct OCRResult: Equatable {
    let fullText: String
    let lines: [OCRRecognizedLine]
    let candidates: OCRExtractedCandidates
    /// OCR extraction is advisory. UI must present candidates for confirmation
    /// and this service never writes them to an order.
    let requiresUserConfirmation: Bool
    let limitations: String

    static func == (lhs: OCRResult, rhs: OCRResult) -> Bool {
        lhs.fullText == rhs.fullText &&
        lhs.lines == rhs.lines &&
        lhs.candidates == rhs.candidates &&
        lhs.requiresUserConfirmation == rhs.requiresUserConfirmation &&
        lhs.limitations == rhs.limitations
    }
}

enum OCREngineError: LocalizedError {
    case invalidImage
    case recognitionUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return L("The image could not be read for text recognition.")
        case .recognitionUnavailable:
            return L("Text recognition is not available for this image.")
        }
    }
}

struct OCREngine {
    func recognizeText(data: Data) async throws -> OCRResult {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw OCREngineError.invalidImage
        }
        return try await recognizeText(in: image)
    }

    /// Recognizes multiple document-camera pages without applying any result.
    func recognizeText(dataItems: [Data]) async throws -> OCRResult {
        var pages: [OCRResult] = []
        for data in dataItems {
            pages.append(try await recognizeText(data: data))
        }
        guard let first = pages.first else { throw OCREngineError.invalidImage }
        guard pages.count > 1 else { return first }
        return OCRResult(
            fullText: pages.map(\.fullText).joined(separator: "\n\n"),
            lines: pages.flatMap(\.lines),
            candidates: OCRExtractedCandidates(
                productTitles: pages.flatMap { $0.candidates.productTitles },
                vendors: pages.flatMap { $0.candidates.vendors },
                estimatedDeliveryTexts: pages.flatMap { $0.candidates.estimatedDeliveryTexts },
                orderNumbers: pages.flatMap { $0.candidates.orderNumbers },
                dates: pages.flatMap { $0.candidates.dates },
                totals: pages.flatMap { $0.candidates.totals }
            ),
            requiresUserConfirmation: true,
            limitations: first.limitations
        )
    }

    func recognizeText(in image: CGImage) async throws -> OCRResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.minimumTextHeight = 0.015
                if let supported = try? VNRecognizeTextRequest.supportedRecognitionLanguages(
                    for: .accurate,
                    revision: VNRecognizeTextRequestRevision3
                ) {
                    let languages = ["en-US", "zh-Hans"].filter { supported.contains($0) }
                    if !languages.isEmpty {
                        request.recognitionLanguages = languages
                    }
                }

                do {
                    let handler = VNImageRequestHandler(cgImage: image, options: [:])
                    try handler.perform([request])
                    let observations = request.results ?? []
                    let lines = observations.compactMap { observation -> OCRRecognizedLine? in
                        guard let candidate = observation.topCandidates(1).first else { return nil }
                        return OCRRecognizedLine(
                            text: candidate.string,
                            confidence: Double(candidate.confidence)
                        )
                    }
                    continuation.resume(returning: Self.makeResult(lines: lines))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func makeResult(lines: [OCRRecognizedLine]) -> OCRResult {
        let fullText = lines.map(\.text).joined(separator: "\n")
        return OCRResult(
            fullText: fullText,
            lines: lines,
            candidates: OCRExtractedCandidates(
                productTitles: extractLabeledText(
                    from: lines,
                    labels: #"\b(?:product(?:\s+name)?|item(?:\s+name|\s+description)?|description)\b|商品名称|商品|产品名称|产品|品名"#,
                    confidenceMultiplier: 0.72
                ),
                vendors: extractLabeledText(
                    from: lines,
                    labels: #"\b(?:vendor|seller|merchant|store|sold\s+by)\b|商家|卖家|商户|店铺|供应商"#,
                    confidenceMultiplier: 0.76
                ),
                estimatedDeliveryTexts: extractDeliveryEstimates(from: lines),
                orderNumbers: extractOrderNumbers(from: lines),
                dates: extractDates(from: lines),
                totals: extractTotals(from: lines)
            ),
            requiresUserConfirmation: true,
            limitations: "Text recognition and field extraction can be wrong, especially for product names, sellers, delivery wording, currencies, dates, and similar-looking characters. Confidence is a heuristic hint, not certainty. Review every suggestion and its source line before using it."
        )
    }

    private static func extractLabeledText(
        from lines: [OCRRecognizedLine],
        labels: String,
        confidenceMultiplier: Double
    ) -> [OCRTextCandidate] {
        let pattern = "(?i)(?:\(labels))\\s*[:：\\-–—]?\\s*(.*)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var results: [OCRTextCandidate] = []
        var seen = Set<String>()
        for (index, line) in lines.enumerated() {
            let range = NSRange(line.text.startIndex..., in: line.text)
            guard let match = regex.firstMatch(in: line.text, range: range),
                  match.numberOfRanges > 1 else { continue }
            var value = ""
            if let valueRange = Range(match.range(at: 1), in: line.text) {
                value = cleanedCandidate(String(line.text[valueRange]))
            }
            if value.isEmpty, lines.indices.contains(index + 1) {
                value = cleanedCandidate(lines[index + 1].text)
            }
            guard value.count >= 2 else { continue }
            value = String(value.prefix(240))
            let key = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard seen.insert(key).inserted else { continue }
            results.append(OCRTextCandidate(
                value: value,
                sourceText: line.text,
                confidence: min(0.88, line.confidence * confidenceMultiplier)
            ))
            if results.count == 5 { break }
        }
        return results
    }

    private static func extractDeliveryEstimates(from lines: [OCRRecognizedLine]) -> [OCRTextCandidate] {
        let pattern = #"(?i)\b(?:estimated\s+(?:delivery|arrival)|delivery\s+estimate|expected\s+delivery|estimated\s+ship(?:ping|ment)?|ships?\s+in|arrives?|delivers?)\b|预计(?:送达|交付|发货|到货)|送达时间|交付时间|发货时间|到货时间"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var results: [OCRTextCandidate] = []
        var seen = Set<String>()
        for line in lines {
            let range = NSRange(line.text.startIndex..., in: line.text)
            guard regex.firstMatch(in: line.text, range: range) != nil else { continue }
            let value = cleanedCandidate(line.text)
            guard value.count >= 2 else { continue }
            let key = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard seen.insert(key).inserted else { continue }
            results.append(OCRTextCandidate(
                value: String(value.prefix(300)),
                sourceText: line.text,
                confidence: min(0.85, line.confidence * 0.7)
            ))
            if results.count == 5 { break }
        }
        return results
    }

    private static func cleanedCandidate(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ":：-–—"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractOrderNumbers(from lines: [OCRRecognizedLine]) -> [OCRTextCandidate] {
        let pattern = #"(?i)\b(?:order(?:\s+(?:number|no\.?))?|confirmation(?:\s+(?:number|no\.?))?)\s*[:#\-]?\s*([A-Z0-9][A-Z0-9\-]{4,29})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var results: [OCRTextCandidate] = []
        var seen = Set<String>()
        for line in lines {
            let range = NSRange(line.text.startIndex..., in: line.text)
            for match in regex.matches(in: line.text, range: range) {
                guard match.numberOfRanges > 1,
                      let valueRange = Range(match.range(at: 1), in: line.text) else { continue }
                let value = String(line.text[valueRange]).uppercased()
                guard seen.insert(value).inserted else { continue }
                results.append(OCRTextCandidate(
                    value: value,
                    sourceText: line.text,
                    confidence: min(0.95, line.confidence * 0.85)
                ))
            }
        }
        return results
    }

    private static func extractDates(from lines: [OCRRecognizedLine]) -> [OCRDateCandidate] {
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.date.rawValue
        ) else { return [] }
        var results: [OCRDateCandidate] = []
        var seen = Set<Date>()
        for line in lines {
            let range = NSRange(line.text.startIndex..., in: line.text)
            let matches = detector.matches(in: line.text, options: [], range: range)
            for match in matches {
                guard let date = match.date, seen.insert(date).inserted else { continue }
                results.append(OCRDateCandidate(
                    value: date,
                    sourceText: line.text,
                    confidence: min(0.9, line.confidence * 0.75)
                ))
            }
        }
        return results
    }

    private static func extractTotals(from lines: [OCRRecognizedLine]) -> [OCRAmountCandidate] {
        let pattern = #"(?i)\b(?:grand\s+total|order\s+total|total\s+amount|total)\s*[:\-]?\s*(?:(USD|EUR|GBP|JPY|CNY|CAD|AUD|HKD)\s*|([$€£¥]))?\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let symbolCurrencies = ["$": "USD", "€": "EUR", "£": "GBP", "¥": "JPY"]
        var results: [OCRAmountCandidate] = []
        var seen = Set<String>()
        for line in lines {
            let range = NSRange(line.text.startIndex..., in: line.text)
            for match in regex.matches(in: line.text, range: range) {
                guard match.numberOfRanges == 4,
                      let amountRange = Range(match.range(at: 3), in: line.text) else { continue }
                let amountText = String(line.text[amountRange]).replacingOccurrences(of: ",", with: "")
                guard let amount = Decimal(string: amountText, locale: Locale(identifier: "en_US_POSIX")) else { continue }

                var currencyCode: String?
                if let codeRange = Range(match.range(at: 1), in: line.text) {
                    currencyCode = String(line.text[codeRange]).uppercased()
                } else if let symbolRange = Range(match.range(at: 2), in: line.text) {
                    currencyCode = symbolCurrencies[String(line.text[symbolRange])]
                }
                let key = "\(amountText)|\(currencyCode ?? "")"
                guard seen.insert(key).inserted else { continue }
                // A currency symbol such as $ or ¥ is ambiguous; UI should not
                // silently accept the suggested code without confirmation.
                let currencyPenalty = currencyCode == nil ? 0.55 : 0.75
                results.append(OCRAmountCandidate(
                    value: amount,
                    currencyCode: currencyCode,
                    sourceText: line.text,
                    confidence: min(0.9, line.confidence * currencyPenalty)
                ))
            }
        }
        return results
    }
}
