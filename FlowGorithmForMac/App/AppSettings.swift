import FlowCore
import SwiftUI

/// Keys and defaults for user preferences, read with @AppStorage.
enum SettingsKey {
    static let theme = "theme"
    static let fontSize = "chartFontSize"
    static let showGrid = "showGrid"
    static let chatConsole = "chatConsole"
    static let runSpeed = "runSpeed"
    static let sourceLanguage = "sourceLanguage"
    static let compactLayout = "compactLayout"
    static let maxStack = "maxStack"
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, italian = "it", english = "en"

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .italian: "Italiano"
        case .english: "English"
        }
    }

    /// The language chosen for this app only, stored where macOS looks for it at launch.
    static var current: AppLanguage {
        get {
            guard let languages = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String],
                  UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["AppleLanguages"] != nil,
                  let first = languages.first else { return .system }
            return first.hasPrefix("it") ? .italian : first.hasPrefix("en") ? .english : .system
        }
        set {
            if newValue == .system {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.set([newValue.rawValue], forKey: "AppleLanguages")
            }
        }
    }
}
