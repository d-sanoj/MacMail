import AppKit
import Foundation
import Network

struct GoogleOAuthClientConfig: Decodable {
    struct Installed: Decodable {
        let clientId: String
        let clientSecret: String
        let authURI: URL
        let tokenURI: URL
        let redirectURIs: [String]

        enum CodingKeys: String, CodingKey {
            case clientId = "client_id"
            case clientSecret = "client_secret"
            case authURI = "auth_uri"
            case tokenURI = "token_uri"
            case redirectURIs = "redirect_uris"
        }
    }

    let installed: Installed
}

struct OAuthAccountProfile: Decodable {
    let email: String
    let name: String?
    let picture: URL?
}

final class GoogleOAuthService {
    private let tokenStore: TokenStoring
    private let session: URLSession
    private let scopes = [
        "https://www.googleapis.com/auth/gmail.modify",
        "https://www.googleapis.com/auth/gmail.labels",
        "https://www.googleapis.com/auth/gmail.compose",
        "https://www.googleapis.com/auth/gmail.send",
        "openid",
        "email",
        "profile"
    ]

    init(tokenStore: TokenStoring, session: URLSession = .shared) {
        self.tokenStore = tokenStore
        self.session = session
    }

    func signIn() async throws -> GmailAccount {
        let config = try loadConfig()
        guard !config.installed.clientId.contains("REPLACE_WITH") else {
            throw MailActionError.missingOAuthConfiguration
        }

        let redirectServer = try LocalOAuthRedirectServer()
        let redirectPort = try await redirectServer.start()
        let redirectURI = "http://127.0.0.1:\(redirectPort)"
        let state = UUID().uuidString

        var components = URLComponents(url: config.installed.authURI, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: config.installed.clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "state", value: state)
        ]
        guard let authURL = components?.url else {
            throw MailActionError.missingOAuthConfiguration
        }

        NSWorkspace.shared.open(authURL)
        let callback = try await redirectServer.waitForCallback(timeoutSeconds: 180)

        if callback.error != nil {
            throw MailActionError.invalidOAuthCallback
        }

        guard callback.state == state, let code = callback.code else {
            throw MailActionError.invalidOAuthCallback
        }

        let tokens = try await exchangeCode(code, redirectURI: redirectURI, config: config)
        let profile = try await fetchProfile(accessToken: tokens.accessToken)
        let accountId = profile.email.lowercased()
        try tokenStore.saveTokens(tokens, accountId: accountId)

        return GmailAccount(
            id: accountId,
            email: profile.email,
            displayName: profile.name ?? profile.email,
            avatarURL: profile.picture,
            isActive: true
        )
    }

    func validAccessToken(for account: GmailAccount) async throws -> String {
        guard var tokens = try tokenStore.tokens(for: account.id) else {
            throw MailActionError.missingActiveAccount
        }
        if tokens.expiresAt.timeIntervalSinceNow > 60 {
            return tokens.accessToken
        }
        tokens = try await refresh(tokens: tokens)
        try tokenStore.saveTokens(tokens, accountId: account.id)
        return tokens.accessToken
    }

    func removeAccount(_ account: GmailAccount) throws {
        try tokenStore.removeTokens(for: account.id)
    }

    func hasStoredTokens(for account: GmailAccount) -> Bool {
        (try? tokenStore.tokens(for: account.id)) != nil
    }

    private func loadConfig() throws -> GoogleOAuthClientConfig {
        try GoogleOAuthClientStore.loadConfig()
    }

    private func exchangeCode(_ code: String, redirectURI: String, config: GoogleOAuthClientConfig) async throws -> OAuthTokenSet {
        var request = URLRequest(url: config.installed.tokenURI)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            "code": code,
            "client_id": config.installed.clientId,
            "client_secret": config.installed.clientSecret,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code"
        ])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw MailActionError.tokenExchangeFailed
        }
        return try decodeTokenResponse(data)
    }

    private func refresh(tokens: OAuthTokenSet) async throws -> OAuthTokenSet {
        guard let refreshToken = tokens.refreshToken else {
            throw MailActionError.tokenExchangeFailed
        }
        let config = try loadConfig()
        var request = URLRequest(url: config.installed.tokenURI)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            "client_id": config.installed.clientId,
            "client_secret": config.installed.clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw MailActionError.tokenExchangeFailed
        }
        var refreshed = try decodeTokenResponse(data)
        refreshed.refreshToken = refreshed.refreshToken ?? refreshToken
        return refreshed
    }

    private func fetchProfile(accessToken: String) async throws -> OAuthAccountProfile {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw MailActionError.apiFailure("Unable to load Google account profile.")
        }
        return try JSONDecoder().decode(OAuthAccountProfile.self, from: data)
    }

    private func decodeTokenResponse(_ data: Data) throws -> OAuthTokenSet {
        struct Response: Decodable {
            let accessToken: String
            let refreshToken: String?
            let expiresIn: TimeInterval
            let scope: String?
            let tokenType: String

            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case refreshToken = "refresh_token"
                case expiresIn = "expires_in"
                case scope
                case tokenType = "token_type"
            }
        }

        let response = try JSONDecoder().decode(Response.self, from: data)
        return OAuthTokenSet(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt: Date().addingTimeInterval(response.expiresIn),
            scope: response.scope,
            tokenType: response.tokenType
        )
    }

    private func formBody(_ values: [String: String]) -> Data {
        values
            .map { key, value in
                "\(key.urlFormEncoded)=\(value.urlFormEncoded)"
            }
            .joined(separator: "&")
            .data(using: .utf8) ?? Data()
    }
}

private final class LocalOAuthRedirectServer: @unchecked Sendable {
    struct Callback {
        let code: String?
        let state: String?
        let error: String?
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "GmailBox.OAuthRedirectServer")
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var callbackContinuation: CheckedContinuation<Callback, Error>?
    private var pendingCallback: Callback?

    init() throws {
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener
    }

    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            startContinuation = continuation
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.startContinuation?.resume()
                    self.startContinuation = nil
                case .failed(let error):
                    self.startContinuation?.resume(throwing: error)
                    self.startContinuation = nil
                case .cancelled:
                    self.startContinuation = nil
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: queue)
        }
        guard let rawPort = listener.port?.rawValue, rawPort != 0 else {
            throw MailActionError.invalidOAuthCallback
        }
        return rawPort
    }

    func waitForCallback(timeoutSeconds: UInt64) async throws -> Callback {
        try await withThrowingTaskGroup(of: Callback.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    self.queue.async {
                        if let pendingCallback = self.pendingCallback {
                            self.pendingCallback = nil
                            continuation.resume(returning: pendingCallback)
                        } else {
                            self.callbackContinuation = continuation
                        }
                    }
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
                throw MailActionError.oauthTimedOut
            }

            guard let callback = try await group.next() else {
                throw MailActionError.oauthTimedOut
            }
            group.cancelAll()
            listener.cancel()
            return callback
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, error in
            guard let self else { return }
            if let error {
                self.fail(error)
                connection.cancel()
                return
            }
            guard let data, let request = String(data: data, encoding: .utf8) else {
                self.fail(MailActionError.invalidOAuthCallback)
                connection.cancel()
                return
            }
            let callback = self.parse(request: request)
            if callback.code != nil || callback.error != nil {
                self.sendResponse(on: connection, success: callback.error == nil)
                self.listener.cancel()
                self.complete(callback)
            } else {
                self.sendResponse(on: connection, success: false, body: "GmailBox is waiting for the Google sign-in callback. You can close this tab.")
            }
        }
    }

    private func complete(_ callback: Callback) {
        if let callbackContinuation {
            self.callbackContinuation = nil
            callbackContinuation.resume(returning: callback)
        } else {
            pendingCallback = callback
        }
    }

    private func fail(_ error: Error) {
        callbackContinuation?.resume(throwing: error)
        callbackContinuation = nil
    }

    private func parse(request: String) -> Callback {
        guard let firstLine = request.components(separatedBy: "\r\n").first,
              let path = firstLine.split(separator: " ").dropFirst().first,
              let url = URL(string: "http://127.0.0.1\(path)") else {
            return Callback(code: nil, state: nil, error: nil)
        }
        guard url.path == "/" || url.path == "/oauth2redirect" else {
            return Callback(code: nil, state: nil, error: nil)
        }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Callback(
            code: items.first(where: { $0.name == "code" })?.value,
            state: items.first(where: { $0.name == "state" })?.value,
            error: items.first(where: { $0.name == "error" })?.value
        )
    }

    private func sendResponse(on connection: NWConnection, success: Bool, body customBody: String? = nil) {
        let body = customBody ?? (success ? "GmailBox sign-in is complete. You can return to the app." : "GmailBox could not complete sign-in. Return to the app and try again.")
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: text/plain; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
