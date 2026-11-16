import SwiftUI
import VisionKit

/// Live text scanner for iOS 16+. Check `DocumentScanner.isSupported` before
/// presenting it. Unsupported devices should use the existing manual image +
/// OCREngine flow instead; this type does not present an unsupported scanner.
@available(iOS 16.0, *)
struct DocumentScanner: UIViewControllerRepresentable {
    typealias UIViewControllerType = DataScannerViewController

    static var isSupported: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    static var unavailableReason: String {
        if !DataScannerViewController.isSupported {
            return "Live text scanning is not supported on this device. Choose an image for OCR instead."
        }
        if !DataScannerViewController.isAvailable {
            return "The camera is currently unavailable. Choose an image for OCR instead."
        }
        return ""
    }

    var isScanning: Bool = true
    var onText: (String) -> Void
    var onError: (String) -> Void

    init(
        isScanning: Bool = true,
        onText: @escaping (String) -> Void,
        onError: @escaping (String) -> Void
    ) {
        self.isScanning = isScanning
        self.onText = onText
        self.onError = onError
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onText: onText, onError: onError)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .balanced,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(
        _ scanner: DataScannerViewController,
        context: Context
    ) {
        context.coordinator.onText = onText
        context.coordinator.onError = onError
        guard Self.isSupported else { return }

        if isScanning && !scanner.isScanning {
            do {
                try scanner.startScanning()
            } catch {
                context.coordinator.onError("Live text scanning could not start. Check camera permission or choose an image for OCR instead.")
            }
        } else if !isScanning && scanner.isScanning {
            scanner.stopScanning()
        }
    }

    static func dismantleUIViewController(
        _ scanner: DataScannerViewController,
        coordinator: Coordinator
    ) {
        if scanner.isScanning {
            scanner.stopScanning()
        }
        scanner.delegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onText: (String) -> Void
        var onError: (String) -> Void

        init(onText: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
            self.onText = onText
            self.onError = onError
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [DataScannerViewController.RecognizedData],
            allItems: [DataScannerViewController.RecognizedData]
        ) {
            for item in addedItems {
                switch item {
                case .text(let text):
                    let transcript = text.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !transcript.isEmpty {
                        onText(transcript)
                    }
                case .barcode:
                    break
                @unknown default:
                    break
                }
            }
        }
    }
}
