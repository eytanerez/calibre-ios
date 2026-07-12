import Foundation
import Security

/// Access/refresh token pair as returned by login/register/refresh.
public struct TokenPair: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String?

    public init(accessToken: String, refreshToken: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }
}

/// Keychain-backed token storage. Tokens are opaque strings — never decode
/// their claims client-side (the backend may migrate token formats).
public protocol TokenStoring: Sendable {
    func load() -> TokenPair?
    func save(_ tokens: TokenPair)
    func clear()
}

public struct KeychainTokenStore: TokenStoring {
    private let service = "com.buycalibre.calibre.tokens"
    private let account = "session"

    public init() {}

    public func load() -> TokenPair? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let tokens = try? JSONDecoder().decode(TokenPair.self, from: data) else {
            return nil
        }
        return tokens
    }

    public func save(_ tokens: TokenPair) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        }
    }

    public func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

/// In-memory store for tests and previews.
public final class MemoryTokenStore: TokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: TokenPair?

    public init(tokens: TokenPair? = nil) {
        self.tokens = tokens
    }

    public func load() -> TokenPair? {
        lock.withLock { tokens }
    }

    public func save(_ tokens: TokenPair) {
        lock.withLock { self.tokens = tokens }
    }

    public func clear() {
        lock.withLock { tokens = nil }
    }
}
