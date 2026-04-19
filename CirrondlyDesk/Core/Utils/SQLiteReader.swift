import Foundation
import SQLite3

enum SQLiteReaderError: Error {
    case openFailed
    case prepareFailed
}

final class SQLiteReader {
    func query(databaseURL: URL, sql: String) throws -> [[String: String]] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw SQLiteReaderError.openFailed
        }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteReaderError.prepareFailed
        }
        defer { sqlite3_finalize(statement) }

        var rows: [[String: String]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: String] = [:]
            let columnCount = sqlite3_column_count(statement)
            for index in 0..<columnCount {
                let key = String(cString: sqlite3_column_name(statement, index))
                if let cValue = sqlite3_column_text(statement, index) {
                    row[key] = String(cString: cValue)
                } else {
                    row[key] = ""
                }
            }
            rows.append(row)
        }

        return rows
    }
}