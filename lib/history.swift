import Foundation
import SQLite3

struct HistoryRecord: Codable {
    let title: String
    let url: String
    let visitedAt: String

    enum CodingKeys: String, CodingKey {
        case title
        case url
        case visitedAt = "visited_at"
    }
}

enum HistoryError: LocalizedError {
    case missingPath
    case invalidArguments
    case openFailed(String)
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingPath:
            return "a History.db path is required"
        case .invalidArguments:
            return "expected a History.db path and optionally --json"
        case .openFailed(let message):
            return "could not open the history database: \(message)"
        case .queryFailed(let message):
            return "could not query the history database: \(message)"
        }
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("Error: " + message + "\n").utf8))
    exit(1)
}

func sqliteMessage(_ database: OpaquePointer?) -> String {
    guard let database = database, let message = sqlite3_errmsg(database) else {
        return "unknown SQLite error"
    }
    return String(cString: message)
}

final class ReadOnlyDatabase {
    private var handle: OpaquePointer?

    init(path: String) throws {
        let result = sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY, nil)
        guard result == SQLITE_OK else {
            let message = sqliteMessage(handle)
            sqlite3_close(handle)
            handle = nil
            throw HistoryError.openFailed(message)
        }

        sqlite3_busy_timeout(handle, 5000)
    }

    deinit {
        sqlite3_close(handle)
    }

    func historyRecords() throws -> [HistoryRecord] {
        let sql = """
        SELECT history_visits.title, history_items.url, history_visits.visit_time
        FROM history_visits
        JOIN history_items ON history_items.id = history_visits.history_item
        ORDER BY history_visits.visit_time DESC, history_visits.id DESC
        """

        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK else {
            throw HistoryError.queryFailed(sqliteMessage(handle))
        }
        defer {
            sqlite3_finalize(statement)
        }

        var records: [HistoryRecord] = []
        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_DONE {
                break
            }

            guard stepResult == SQLITE_ROW else {
                throw HistoryError.queryFailed(sqliteMessage(handle))
            }

            guard let url = nonEmptyString(columnString(statement, index: 1)) else {
                throw HistoryError.queryFailed("history item has no URL")
            }

            let title = nonEmptyString(columnString(statement, index: 0)) ?? url
            let visitType = sqlite3_column_type(statement, 2)
            guard visitType == SQLITE_INTEGER || visitType == SQLITE_FLOAT else {
                throw HistoryError.queryFailed("history visit has an invalid visit time")
            }

            let visitTime = sqlite3_column_double(statement, 2)
            guard visitTime.isFinite else {
                throw HistoryError.queryFailed("history visit has an invalid visit time")
            }

            records.append(
                HistoryRecord(
                    title: title,
                    url: url,
                    visitedAt: iso8601Date(visitTime)
                )
            )
        }

        return records
    }
}

func columnString(_ statement: OpaquePointer?, index: Int32) -> String? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL,
          let value = sqlite3_column_text(statement, index) else {
        return nil
    }
    return String(cString: value)
}

func nonEmptyString(_ value: String?) -> String? {
    guard let value = value, !value.isEmpty else {
        return nil
    }
    return value
}

func iso8601Date(_ referenceTime: Double) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: Date(timeIntervalSinceReferenceDate: referenceTime))
}

func humanDate(_ isoDate: String) -> String {
    let parser = ISO8601DateFormatter()
    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    guard let date = parser.date(from: isoDate) else {
        return isoDate
    }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter.string(from: date)
}

func humanText(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\r", with: " ")
        .replacingOccurrences(of: "\n", with: " ")
}

func writeJSON(_ records: [HistoryRecord]) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(records)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

func writeHumanReadable(_ records: [HistoryRecord]) {
    if records.isEmpty {
        print("No history entries found.")
        return
    }

    for record in records {
        print("- \(humanText(record.title))")
        print("  \(humanDate(record.visitedAt))")
        print("  \(humanText(record.url))")
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
var jsonOutput = false
var historyPath: String?

for argument in arguments {
    if argument == "--json" {
        jsonOutput = true
    } else if historyPath == nil {
        historyPath = argument
    } else {
        fail(HistoryError.invalidArguments.localizedDescription)
    }
}

guard let historyPath = historyPath else {
    fail(HistoryError.missingPath.localizedDescription)
}

do {
    let database = try ReadOnlyDatabase(path: historyPath)
    let records = try database.historyRecords()

    if jsonOutput {
        try writeJSON(records)
    } else {
        writeHumanReadable(records)
    }
} catch {
    fail("could not read or parse '\(historyPath)': \(error.localizedDescription)")
}
