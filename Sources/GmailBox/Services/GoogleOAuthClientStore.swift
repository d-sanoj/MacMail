import Foundation

struct GoogleOAuthClientSummary: Equatable {
    var isConfigured: Bool
    var clientIdPreview: String
    var sourceDescription: String
}

enum GoogleOAuthClientStore {
    private static let filename = "GoogleOAuthClient.json"

    static var userConfigURL: URL {
        applicationSupportDirectory.appending(path: filename)
    }

    static var applicationSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "GmailBox", directoryHint: .isDirectory)
    }

    static func loadConfig() throws -> GoogleOAuthClientConfig {
        if FileManager.default.fileExists(atPath: userConfigURL.path) {
            return try loadConfig(from: userConfigURL)
        }

        throw MailActionError.missingOAuthConfiguration
    }

    static func importConfig(from sourceURL: URL) throws -> GoogleOAuthClientSummary {
        let config = try loadConfig(from: sourceURL)
        try validate(config)
        try FileManager.default.createDirectory(at: applicationSupportDirectory, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: userConfigURL.path) {
            try FileManager.default.removeItem(at: userConfigURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: userConfigURL)

        return summary(for: config, sourceDescription: "Stored in Application Support")
    }

    static func removeImportedConfig() throws {
        if FileManager.default.fileExists(atPath: userConfigURL.path) {
            try FileManager.default.removeItem(at: userConfigURL)
        }
    }

    static func currentSummary() -> GoogleOAuthClientSummary {
        do {
            let usesImportedConfig = FileManager.default.fileExists(atPath: userConfigURL.path)
            let config = try loadConfig()
            return summary(
                for: config,
                sourceDescription: usesImportedConfig ? "Stored in Application Support" : "Not configured"
            )
        } catch {
            return GoogleOAuthClientSummary(
                isConfigured: false,
                clientIdPreview: "Not configured",
                sourceDescription: "No readable OAuth client JSON"
            )
        }
    }

    private static func loadConfig(from url: URL) throws -> GoogleOAuthClientConfig {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(GoogleOAuthClientConfig.self, from: data)
    }

    private static func validate(_ config: GoogleOAuthClientConfig) throws {
        let installed = config.installed
        guard !installed.clientId.isEmpty,
              !installed.clientSecret.isEmpty,
              !installed.clientId.contains("REPLACE_WITH"),
              !installed.clientSecret.contains("REPLACE_WITH"),
              installed.authURI.absoluteString.contains("accounts.google.com"),
              installed.tokenURI.absoluteString.contains("oauth2.googleapis.com") else {
            throw MailActionError.missingOAuthConfiguration
        }
    }

    private static func summary(for config: GoogleOAuthClientConfig, sourceDescription: String) -> GoogleOAuthClientSummary {
        let clientId = config.installed.clientId
        let preview: String
        if clientId.contains("REPLACE_WITH") {
            preview = "Placeholder client"
        } else if clientId.count > 18 {
            preview = "\(clientId.prefix(10))...\(clientId.suffix(8))"
        } else {
            preview = clientId
        }

        return GoogleOAuthClientSummary(
            isConfigured: !clientId.contains("REPLACE_WITH"),
            clientIdPreview: preview,
            sourceDescription: sourceDescription
        )
    }
}
