import Foundation
import SQLite3

final class SQLiteCacheStore {
    private let databaseURL: URL
    private var database: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(databaseURL: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "GmailBox/GmailBox.sqlite")) {
        self.databaseURL = databaseURL
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    deinit {
        sqlite3_close(database)
    }

    func open() throws {
        try FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK else {
            throw MailActionError.cacheFailure(lastError)
        }
        try execute("""
        CREATE TABLE IF NOT EXISTS cached_objects (
            kind TEXT NOT NULL,
            id TEXT NOT NULL,
            account_id TEXT NOT NULL,
            payload BLOB NOT NULL,
            updated_at REAL NOT NULL,
            PRIMARY KEY(kind, id, account_id)
        );
        """)
    }

    func saveAccounts(_ accounts: [GmailAccount]) throws {
        try delete(kind: "account", accountId: "global")
        try save(accounts, kind: "account", accountId: "global") { $0.id }
    }

    func loadAccounts() throws -> [GmailAccount] {
        try load(kind: "account", accountId: "global", as: GmailAccount.self)
    }

    func saveLabels(_ labels: [GmailLabel], accountId: String) throws {
        try delete(kind: "label", accountId: accountId)
        try save(labels, kind: "label", accountId: accountId) { $0.id }
    }

    func loadLabels(accountId: String) throws -> [GmailLabel] {
        try load(kind: "label", accountId: accountId, as: GmailLabel.self)
    }

    func saveThreads(_ threads: [GmailThread], accountId: String) throws {
        try delete(kind: "thread", accountId: accountId)
        try save(threads, kind: "thread", accountId: accountId) { $0.id }
    }

    func loadThreads(accountId: String) throws -> [GmailThread] {
        try load(kind: "thread", accountId: accountId, as: GmailThread.self)
    }

    func saveMessages(_ messages: [GmailMessage], accountId: String) throws {
        try save(messages, kind: "message", accountId: accountId) { $0.id }
    }

    func loadMessages(threadId: String, accountId: String) throws -> [GmailMessage] {
        try load(kind: "message", accountId: accountId, as: GmailMessage.self).filter { $0.threadId == threadId }
    }

    func saveSyncState(_ state: SyncState) throws {
        try save([state], kind: "sync_state", accountId: state.accountId) { $0.accountId }
    }

    func loadSyncState(accountId: String) throws -> SyncState? {
        try load(kind: "sync_state", accountId: accountId, as: SyncState.self).first
    }

    private func save<T: Encodable>(_ values: [T], kind: String, accountId: String, id: (T) -> String) throws {
        guard database != nil else { try open(); return try save(values, kind: kind, accountId: accountId, id: id) }
        let sql = "INSERT OR REPLACE INTO cached_objects(kind, id, account_id, payload, updated_at) VALUES (?, ?, ?, ?, ?);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw MailActionError.cacheFailure(lastError)
        }
        defer { sqlite3_finalize(statement) }

        for value in values {
            let data = try encoder.encode(value)
            sqlite3_bind_text(statement, 1, kind, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, id(value), -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, accountId, -1, SQLITE_TRANSIENT)
            _ = data.withUnsafeBytes { buffer in
                sqlite3_bind_blob(statement, 4, buffer.baseAddress, Int32(data.count), SQLITE_TRANSIENT)
            }
            sqlite3_bind_double(statement, 5, Date().timeIntervalSince1970)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw MailActionError.cacheFailure(lastError)
            }
            sqlite3_reset(statement)
        }
    }

    private func load<T: Decodable>(kind: String, accountId: String, as type: T.Type) throws -> [T] {
        guard database != nil else { try open(); return try load(kind: kind, accountId: accountId, as: type) }
        let sql = "SELECT payload FROM cached_objects WHERE kind = ? AND account_id = ? ORDER BY updated_at DESC;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw MailActionError.cacheFailure(lastError)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, kind, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, accountId, -1, SQLITE_TRANSIENT)

        var values: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let bytes = sqlite3_column_blob(statement, 0)
            let count = Int(sqlite3_column_bytes(statement, 0))
            guard let bytes else { continue }
            let data = Data(bytes: bytes, count: count)
            values.append(try decoder.decode(T.self, from: data))
        }
        return values
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw MailActionError.cacheFailure(lastError)
        }
    }

    private func delete(kind: String, accountId: String) throws {
        guard database != nil else { try open(); return try delete(kind: kind, accountId: accountId) }
        let sql = "DELETE FROM cached_objects WHERE kind = ? AND account_id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw MailActionError.cacheFailure(lastError)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, kind, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, accountId, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw MailActionError.cacheFailure(lastError)
        }
    }

    private var lastError: String {
        guard let database, let message = sqlite3_errmsg(database) else {
            return "Unknown SQLite error."
        }
        return String(cString: message)
    }
}
