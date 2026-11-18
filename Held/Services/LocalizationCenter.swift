import Foundation

/// The user's presentation language. Persisted raw values are deliberately stable
/// because they are also included in backups and must never be translated.
enum AppLanguage: String, CaseIterable, Codable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    init(rawValueOrSystem rawValue: String?) {
        self = AppLanguage(rawValue: rawValue ?? "") ?? .system
    }

    var locale: Locale {
        switch self {
        case .system: return .current
        case .english: return Locale(identifier: "en_US")
        case .simplifiedChinese: return Locale(identifier: "zh_CN")
        }
    }

    /// The name is intentionally written in the language it represents so a
    /// user can always find the way back, regardless of the current interface.
    var nativeDisplayName: String {
        switch self {
        case .system: return "System / 跟随系统"
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        }
    }

    fileprivate var resourceName: String? {
        switch self {
        case .system: return nil
        case .english: return "en"
        case .simplifiedChinese: return "zh-Hans"
        }
    }
}

/// Resolves strings from the selected language bundle without changing the
/// device's system language. Views observe `language` and re-render in place.
final class LocalizationCenter: ObservableObject {
    static let shared = LocalizationCenter()

    @Published private(set) var language: AppLanguage

    private init() {
        let saved = UserDefaults.standard.string(forKey: "preferredLanguageRaw")
        language = AppLanguage(rawValueOrSystem: saved)
    }

    var locale: Locale { language.locale }

    func setLanguage(_ newValue: AppLanguage) {
        guard newValue != language else { return }
        language = newValue
        UserDefaults.standard.set(newValue.rawValue, forKey: "preferredLanguageRaw")
    }

    func text(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }

    func text(_ key: String, _ arguments: CVarArg...) -> String {
        formattedText(key, arguments: arguments)
    }

    func formattedText(_ key: String, arguments: [CVarArg]) -> String {
        let format = text(key)
        return String(format: format, locale: locale, arguments: arguments)
    }

    private var bundle: Bundle {
        guard let resourceName = language.resourceName,
              let path = Bundle.main.path(forResource: resourceName, ofType: "lproj"),
              let localizedBundle = Bundle(path: path) else {
            return .main
        }
        return localizedBundle
    }
}

/// A compact call site for static labels. Dynamic and persisted strings should
/// use semantic keys through the same center rather than translating raw values.
func L(_ key: String) -> String {
    LocalizationCenter.shared.text(key)
}

func L(_ key: String, _ arguments: CVarArg...) -> String {
    LocalizationCenter.shared.formattedText(key, arguments: arguments)
}
