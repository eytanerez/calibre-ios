import SwiftUI

/// The user's chosen appearance — System follows the device setting; Light
/// and Dark pin the app regardless of it. Stored directly via `@AppStorage`
/// (String-backed `RawRepresentable` works with the property wrapper as-is).
public enum AppearancePreference: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// What to hand `.preferredColorScheme(_:)` — nil defers to the device.
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
