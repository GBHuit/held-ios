import Foundation
import Combine

/// Target-local presentation localization. The share extension cannot access the
/// main app's LocalizationCenter, so it resolves the same English keys from its
/// own string catalog and falls back to the system language.
final class ShareLocalizationCenter: ObservableObject {
    static let shared = ShareLocalizationCenter()

    @Published private(set) var preferredLanguageRaw: String

    private init() {
        let sharedDefaults = UserDefaults(suiteName: "group.com.held.groupbuy")
        preferredLanguageRaw = sharedDefaults?.string(forKey: "preferredLanguageRaw")
            ?? UserDefaults.standard.string(forKey: "preferredLanguageRaw")
            ?? "system"
    }

    var locale: Locale {
        switch preferredLanguageRaw {
        case "en": return Locale(identifier: "en_US")
        case "zh-Hans": return Locale(identifier: "zh_CN")
        default: return .current
        }
    }

    func text(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }

    func formattedText(_ key: String, arguments: [CVarArg]) -> String {
        String(format: text(key), locale: locale, arguments: arguments)
    }

    private var bundle: Bundle {
        let resourceName: String?
        switch preferredLanguageRaw {
        case "en": resourceName = "en"
        case "zh-Hans": resourceName = "zh-Hans"
        default: resourceName = nil
        }
        guard let resourceName,
              let path = Bundle.main.path(forResource: resourceName, ofType: "lproj"),
              let localizedBundle = Bundle(path: path) else {
            return .main
        }
        return localizedBundle
    }
}

func L(_ key: String) -> String {
    ShareLocalizationCenter.shared.text(key)
}

func L(_ key: String, _ arguments: CVarArg...) -> String {
    ShareLocalizationCenter.shared.formattedText(key, arguments: arguments)
}
