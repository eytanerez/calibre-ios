import SwiftUI

/// Circular monogram avatar for sellers and buyers without a photo — warm
/// accent circle with serif initials. Initials are true initials (capital
/// letters), not a styled uppercase treatment.
public struct AvatarInitial: View {
    /// Fixed avatar sizes: s = 28pt (inline rows), m = 40pt (list rows),
    /// l = 56pt (profile headers).
    public enum Size {
        case s, m, l

        var diameter: CGFloat {
            switch self {
            case .s: 28
            case .m: 40
            case .l: 56
            }
        }

        var fontSize: CGFloat {
            switch self {
            case .s: 12
            case .m: 16
            case .l: 22
            }
        }
    }

    let initials: String
    let size: Size
    private let accessibilityName: String?

    /// Exact initials, e.g. `AvatarInitial(initials: "GW")`.
    public init(initials: String, size: Size = .m) {
        self.initials = initials
        self.size = size
        self.accessibilityName = nil
    }

    /// Derives up to two initials from a display name
    /// ("Geneva Watch Co." → "GW").
    public init(name: String, size: Size = .m) {
        let words = name.split(separator: " ").prefix(2)
        self.initials = words.compactMap { $0.first.map(String.init) }.joined().uppercased()
        self.size = size
        self.accessibilityName = name
    }

    public var body: some View {
        Text(initials)
            .font(CalibreType.serif(.medium, size.fontSize))
            .foregroundStyle(Color.calibre.accentForeground)
            .frame(width: size.diameter, height: size.diameter)
            .background(Color.calibre.accent, in: Circle())
            .accessibilityLabel(accessibilityName ?? initials)
    }
}

#Preview("Avatars — light", traits: .sizeThatFitsLayout) {
    HStack(spacing: Space.l) {
        AvatarInitial(name: "Geneva Watch Co.", size: .s)
        AvatarInitial(name: "Geneva Watch Co.", size: .m)
        AvatarInitial(name: "Eytan Erez", size: .l)
    }
    .padding()
    .background(Color.calibre.background)
}

#Preview("Avatars — dark", traits: .sizeThatFitsLayout) {
    HStack(spacing: Space.l) {
        AvatarInitial(name: "Geneva Watch Co.", size: .s)
        AvatarInitial(name: "Geneva Watch Co.", size: .m)
        AvatarInitial(name: "Eytan Erez", size: .l)
    }
    .padding()
    .background(Color.calibre.background)
    .preferredColorScheme(.dark)
}
