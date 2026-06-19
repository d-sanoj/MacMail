import Foundation

struct OAuthTokenSet: Codable, Hashable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
    var scope: String?
    var tokenType: String
}

protocol TokenStoring {
    func saveTokens(_ tokens: OAuthTokenSet, accountId: String) throws
    func tokens(for accountId: String) throws -> OAuthTokenSet?
    func removeTokens(for accountId: String) throws
}

final class LocalTokenStore: TokenStoring {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var memoryCache: [String: OAuthTokenSet] = [:]

    init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func saveTokens(_ tokens: OAuthTokenSet, accountId: String) throws {
        try FileManager.default.createDirectory(at: tokenDirectory, withIntermediateDirectories: true)
        let data = try encoder.encode(tokens)
        try data.write(to: tokenURL(for: accountId), options: [.atomic])
        memoryCache[accountId] = tokens
    }

    func tokens(for accountId: String) throws -> OAuthTokenSet? {
        if let cached = memoryCache[accountId] {
            return cached
        }

        let url = tokenURL(for: accountId)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let tokens = try decoder.decode(OAuthTokenSet.self, from: Data(contentsOf: url))
        memoryCache[accountId] = tokens
        return tokens
    }

    func removeTokens(for accountId: String) throws {
        memoryCache.removeValue(forKey: accountId)
        let url = tokenURL(for: accountId)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private var tokenDirectory: URL {
        GoogleOAuthClientStore.applicationSupportDirectory
            .appending(path: "Tokens", directoryHint: .isDirectory)
    }

    private func tokenURL(for accountId: String) -> URL {
        let safeName = accountId
            .replacingOccurrences(of: "@", with: "_at_")
            .replacingOccurrences(of: ".", with: "_")
        return tokenDirectory.appending(path: "\(safeName).json")
    }
}
