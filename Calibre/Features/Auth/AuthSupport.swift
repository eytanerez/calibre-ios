import CalibreDesign
import CalibreKit
import SwiftUI

/// Mixed-type JSON payload value for auth endpoints whose bodies nest objects
/// (Apple's `full_name`, register's `address`). Keys are written already
/// snake_cased — `JSONEncoder.convertToSnakeCase` leaves them untouched.
enum AuthJSON: Encodable, Sendable {
    case string(String)
    case object([String: AuthJSON])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}

/// GET /auth/username-availability response payload.
struct UsernameAvailability: Decodable, Sendable {
    let username: String
    let available: Bool
    let message: String
}

/// Human copy for the Google native-handoff error codes — mirrors the web
/// login page's mapping, phrased for the brand voice.
enum GoogleAuthError {
    static func message(for code: String) -> String {
        switch code {
        case "google_access_denied":
            "Google sign-in was canceled."
        case "google_not_configured":
            "Google sign-in isn't available yet."
        case "google_state_mismatch":
            "That sign-in attempt expired. Please try again."
        case "google_missing_code":
            "Google didn't return an authorization code. Please try again."
        case "google_token_exchange_failed":
            "We couldn't complete Google sign-in. Please try again."
        case "google_invalid_audience", "google_invalid_issuer":
            "Google sign-in isn't configured correctly for this environment."
        case "google_token_expired":
            "That Google sign-in expired. Please try again."
        case "google_missing_email":
            "Your Google account didn't share an email address."
        case "google_unverified_email":
            "Your Google email address isn't verified yet."
        case "google_unreachable":
            "We couldn't reach Google. Check your connection and try again."
        case "account_not_active":
            "This account isn't active. Contact support if that seems wrong."
        case "phone_required":
            "Create your account with email and phone first, then Google sign-in will work."
        default:
            "Google sign-in didn't go through. Please try again."
        }
    }
}

/// The serif Calibre wordmark used on the login screen and intro.
struct CalibreWordmark: View {
    var size: CGFloat = 34

    var body: some View {
        Text("Calibre")
            .font(CalibreType.serif(.semiBold, size, relativeTo: .largeTitle))
            .foregroundStyle(Color.calibre.foreground)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Quiet "or" divider between credential and social sign-in.
struct AuthDivider: View {
    var body: some View {
        HStack(spacing: Space.m) {
            Rectangle().fill(Color.calibre.border).frame(height: 1)
            Text("or")
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.mutedForeground)
            Rectangle().fill(Color.calibre.border).frame(height: 1)
        }
        .accessibilityHidden(true)
    }
}

/// Inline destructive error line under a form — appears gently.
struct AuthErrorLine: View {
    let message: String

    var body: some View {
        Text(message)
            .font(CalibreType.label)
            .foregroundStyle(Color.calibre.destructive)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity.combined(with: .offset(y: -3)))
    }
}

extension APIError {
    /// The message to surface for an auth failure — always the backend's
    /// words when it spoke, with gentle fallbacks otherwise.
    var authMessage: String {
        switch self {
        case .rateLimited:
            "A moment, please — too many attempts in a row. Try again shortly."
        default:
            errorDescription ?? "Something went wrong. Please try again."
        }
    }
}

/// One shared shape for "run an auth call, surface errors kindly".
@MainActor
func performAuthAction(
    _ action: () async throws -> Void,
    onError: (String) -> Void
) async -> Bool {
    do {
        try await action()
        return true
    } catch let error as APIError {
        Haptics.shared.play(.error)
        onError(error.authMessage)
        return false
    } catch is CancellationError {
        return false
    } catch {
        Haptics.shared.play(.error)
        onError("Something went wrong. Please try again.")
        return false
    }
}
