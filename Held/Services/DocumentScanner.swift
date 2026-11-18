import SwiftUI
import UIKit
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
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
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


/// VisionKit document-camera capture for new-order OCR. The scanned images are
/// returned to the caller for review; this type never writes an order or evidence.
@available(iOS 13.0, *)
struct DocumentCameraScanner: UIViewControllerRepresentable {
    typealias UIViewControllerType = VNDocumentCameraViewController

    static var isSupported: Bool {
        VNDocumentCameraViewController.isSupported
    }

    let onComplete: ([UIImage]) -> Void
    let onCancel: () -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete, onCancel: onCancel, onError: onError)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: VNDocumentCameraViewController, context: Context) {
        context.coordinator.onComplete = onComplete
        context.coordinator.onCancel = onCancel
        context.coordinator.onError = onError
    }

    static func dismantleUIViewController(
        _ scanner: VNDocumentCameraViewController,
        coordinator: Coordinator
    ) {
        scanner.delegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        var onComplete: ([UIImage]) -> Void
        var onCancel: () -> Void
        var onError: (String) -> Void

        init(
            onComplete: @escaping ([UIImage]) -> Void,
            onCancel: @escaping () -> Void,
            onError: @escaping (String) -> Void
        ) {
            self.onComplete = onComplete
            self.onCancel = onCancel
            self.onError = onError
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            let images = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            guard !images.isEmpty else {
                onError("The scan did not contain a readable page. Choose a photo or continue manually.")
                return
            }
            onComplete(images)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
        }
    }
}
