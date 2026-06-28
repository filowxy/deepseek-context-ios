import Foundation
import SQLite3

enum DatabaseError: Error {
    case openFailed(String)
    case execFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case bindingFailed(String)
    case unexpectedNull
}

actor DatabaseManager {
    static let shared = DatabaseManager()

    private var db: OpaquePointer?
    private let isoFormatter: ISO8601DateFormatter

    private init() {
        isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
    }

    func open(databasePath: String? = nil) async throws {
        guard db == nil else { return }

        let dbURL: URL
        if let databasePath {
            dbURL = URL(fileURLWithPath: databasePath)
        } else {
            let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            dbURL = urls[0].appendingPathComponent("deepseek_context.sqlite")
        }

        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(dbURL.path, &db, flags, nil)
        guard rc == SQLITE_OK, let db else {
            let message = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.openFailed(message)
        }

        try exec("PRAGMA foreign_keys = ON;")
        try exec("PRAGMA journal_mode = WAL;")
        try createSchema()
    }

    func close() {
        if let db {
            sqlite3_close_v2(db)
            self.db = nil
        }
    }

    var connection: OpaquePointer {
        get throws {
            guard let db else {
                throw DatabaseError.openFailed("Database is not open")
            }
            return db
        }
    }

    func string(from date: Date) -> String {
        isoFormatter.string(from: date)
    }

    func date(from string: String) -> Date? {
        isoFormatter.date(from: string)
    }

    // MARK: - Schema

    private func createSchema() throws {
        let schema = """
        CREATE TABLE IF NOT EXISTS conversations (
            id TEXT PRIMARY KEY,
            title TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            is_active INTEGER DEFAULT 1
        );

        CREATE TABLE IF NOT EXISTS context_marks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            mark_id INTEGER NOT NULL,
            conversation_id TEXT NOT NULL REFERENCES conversations(id),
            lev INTEGER NOT NULL CHECK(lev IN (0,1,2,3)),
            type TEXT NOT NULL CHECK(type IN ('userask', 'complex')),
            content TEXT NOT NULL,
            idem_key TEXT UNIQUE,
            created_counter INTEGER NOT NULL,
            last_remind_counter INTEGER,
            created_at TEXT NOT NULL,
            deleted INTEGER DEFAULT 0,
            deleted_at TEXT,
            UNIQUE(conversation_id, mark_id)
        );

        CREATE INDEX IF NOT EXISTS idx_context_marks_reminder ON context_marks(conversation_id, deleted, created_counter);

        CREATE TABLE IF NOT EXISTS mark_tags (
            mark_id INTEGER NOT NULL,
            tag TEXT NOT NULL,
            PRIMARY KEY (mark_id, tag),
            FOREIGN KEY (mark_id) REFERENCES context_marks(id) ON DELETE CASCADE
        );

        CREATE INDEX IF NOT EXISTS idx_mark_tags_tag ON mark_tags(tag);

        CREATE TABLE IF NOT EXISTS conversation_links (
            conversation_id TEXT PRIMARY KEY REFERENCES conversations(id),
            parent_conversation_id TEXT REFERENCES conversations(id),
            linked_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS conversation_counter (
            conversation_id TEXT PRIMARY KEY REFERENCES conversations(id),
            count INTEGER DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS global_context (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            content TEXT NOT NULL,
            created_at TEXT NOT NULL,
            deleted INTEGER DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS global_suggestion_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            parent_id INTEGER REFERENCES global_suggestion_log(id),
            content TEXT NOT NULL,
            reason TEXT,
            content_hash TEXT,
            status TEXT NOT NULL CHECK(status IN ('accepted', 'rejected')),
            rejection_feedback TEXT,
            created_at TEXT NOT NULL
        );

        CREATE VIRTUAL TABLE IF NOT EXISTS context_marks_fts USING fts5(
            content,
            content=context_marks,
            content_rowid=id
        );

        DROP TRIGGER IF EXISTS context_marks_ai;
        CREATE TRIGGER context_marks_ai AFTER INSERT ON context_marks BEGIN
            INSERT INTO context_marks_fts(rowid, content) VALUES (new.id, new.content);
        END;

        DROP TRIGGER IF EXISTS context_marks_ad;
        CREATE TRIGGER context_marks_ad AFTER DELETE ON context_marks BEGIN
            INSERT INTO context_marks_fts(context_marks_fts, rowid, content) VALUES('delete', old.id, old.content);
        END;

        DROP TRIGGER IF EXISTS context_marks_au;
        CREATE TRIGGER context_marks_au AFTER UPDATE ON context_marks
        WHEN old.content IS NOT new.content
        BEGIN
            INSERT INTO context_marks_fts(context_marks_fts, rowid, content) VALUES('delete', old.id, old.content);
            INSERT INTO context_marks_fts(rowid, content) VALUES (new.id, new.content);
        END;
        """
        try exec(schema)
    }

    // MARK: - Helpers

    func exec(_ sql: String) throws {
        let db = try connection
        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if rc != SQLITE_OK, let errMsg {
            let message = String(cString: errMsg)
            sqlite3_free(errMsg)
            throw DatabaseError.execFailed(message)
        }
    }

    func prepare(_ sql: String) throws -> OpaquePointer {
        let db = try connection
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let stmt else {
            let message = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.prepareFailed("\(message) | SQL: \(sql)")
        }
        return stmt
    }

    func bindText(_ stmt: OpaquePointer, index: Int, value: String) throws {
        let rc = sqlite3_bind_text(stmt, Int32(index), (value as NSString).utf8String, -1, SQLITE_TRANSIENT)
        guard rc == SQLITE_OK else {
            throw DatabaseError.bindingFailed("bind text failed at \(index)")
        }
    }

    func bindInt64(_ stmt: OpaquePointer, index: Int, value: Int64) throws {
        let rc = sqlite3_bind_int64(stmt, Int32(index), value)
        guard rc == SQLITE_OK else {
            throw DatabaseError.bindingFailed("bind int64 failed at \(index)")
        }
    }

    func bindOptionalInt64(_ stmt: OpaquePointer, index: Int, value: Int64?) throws {
        let rc: Int32
        if let value {
            rc = sqlite3_bind_int64(stmt, Int32(index), value)
        } else {
            rc = sqlite3_bind_null(stmt, Int32(index))
        }
        guard rc == SQLITE_OK else {
            throw DatabaseError.bindingFailed("bind optional int64 failed at \(index)")
        }
    }

    func bindOptionalText(_ stmt: OpaquePointer, index: Int, value: String?) throws {
        let rc: Int32
        if let value {
            rc = sqlite3_bind_text(stmt, Int32(index), (value as NSString).utf8String, -1, SQLITE_TRANSIENT)
        } else {
            rc = sqlite3_bind_null(stmt, Int32(index))
        }
        guard rc == SQLITE_OK else {
            throw DatabaseError.bindingFailed("bind optional text failed at \(index)")
        }
    }

    func columnText(_ stmt: OpaquePointer, index: Int) -> String {
        guard let cString = sqlite3_column_text(stmt, Int32(index)) else { return "" }
        return String(cString: cString)
    }

    func columnOptionalText(_ stmt: OpaquePointer, index: Int) -> String? {
        guard let cString = sqlite3_column_text(stmt, Int32(index)) else { return nil }
        return String(cString: cString)
    }

    func columnInt64(_ stmt: OpaquePointer, index: Int) -> Int64 {
        sqlite3_column_int64(stmt, Int32(index))
    }

    func columnBool(_ stmt: OpaquePointer, index: Int) -> Bool {
        sqlite3_column_int(stmt, Int32(index)) != 0
    }

    func step(_ stmt: OpaquePointer) throws -> Bool {
        let rc = sqlite3_step(stmt)
        if rc == SQLITE_ROW {
            return true
        } else if rc == SQLITE_DONE {
            return false
        } else {
            let message = String(cString: sqlite3_errmsg(try connection))
            sqlite3_finalize(stmt)
            throw DatabaseError.stepFailed(message)
        }
    }

    func lastInsertedRowID() throws -> Int64 {
        sqlite3_last_insert_rowid(try connection)
    }
}
