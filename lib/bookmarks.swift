import Foundation

struct SafariEntry: Codable {
    let title: String
    let url: String
    let path: [String]
}

enum BookmarkError: LocalizedError {
    case missingPath
    case invalidArguments
    case invalidRoot

    var errorDescription: String? {
        switch self {
        case .missingPath:
            return "a Bookmarks.plist path is required"
        case .invalidArguments:
            return "expected a Bookmarks.plist path and optionally --json or --reading-list"
        case .invalidRoot:
            return "the plist root is not a dictionary"
        }
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("Error: " + message + "\n").utf8))
    exit(1)
}

func nonEmptyString(_ value: Any?) -> String? {
    guard let string = value as? String, !string.isEmpty else {
        return nil
    }
    return string
}

func dictionary(_ value: Any?) -> [String: Any]? {
    if let dictionary = value as? [String: Any] {
        return dictionary
    }

    if let dictionary = value as? NSDictionary {
        var result: [String: Any] = [:]
        for (key, value) in dictionary {
            if let key = key as? String {
                result[key] = value
            }
        }
        return result
    }

    return nil
}

func children(of node: [String: Any]) -> [[String: Any]] {
    guard let values = node["Children"] as? [Any] else {
        return []
    }

    return values.compactMap { dictionary($0) }
}

func entryTitle(for node: [String: Any], url: String) -> String {
    if let title = nonEmptyString(node["Title"]) {
        return title
    }

    if let uriDictionary = dictionary(node["URIDictionary"]),
       let title = nonEmptyString(uriDictionary["title"]) {
        return title
    }

    return url
}

func collectBookmarkEntries(
    from node: [String: Any],
    path: [String],
    inReadingList: Bool,
    entries: inout [SafariEntry]
) {
    let nodeTitle = nonEmptyString(node["Title"]) ?? ""
    let isReadingList = inReadingList || nodeTitle == "com.apple.ReadingList"

    if let url = nonEmptyString(node["URLString"]), !isReadingList {
        entries.append(
            SafariEntry(
                title: entryTitle(for: node, url: url),
                url: url,
                path: path
            )
        )
        return
    }

    let childPath = nodeTitle.isEmpty ? path : path + [nodeTitle]
    for child in children(of: node) {
        collectBookmarkEntries(
            from: child,
            path: childPath,
            inReadingList: isReadingList,
            entries: &entries
        )
    }
}

func collectReadingListEntries(
    from node: [String: Any],
    path: [String],
    inReadingList: Bool,
    entries: inout [SafariEntry]
) {
    let nodeTitle = nonEmptyString(node["Title"]) ?? ""
    let isReadingList = inReadingList || nodeTitle == "com.apple.ReadingList"

    if let url = nonEmptyString(node["URLString"]), isReadingList {
        entries.append(
            SafariEntry(
                title: entryTitle(for: node, url: url),
                url: url,
                path: path
            )
        )
        return
    }

    let childPath: [String]
    if !inReadingList && nodeTitle == "com.apple.ReadingList" {
        childPath = path + ["Reading List"]
    } else {
        childPath = path
    }

    for child in children(of: node) {
        collectReadingListEntries(
            from: child,
            path: childPath,
            inReadingList: isReadingList,
            entries: &entries
        )
    }
}

func loadEntries(from path: String, readingList: Bool) throws -> [SafariEntry] {
    let data = try Data(contentsOf: URL(fileURLWithPath: path), options: [.mappedIfSafe])
    var format = PropertyListSerialization.PropertyListFormat.binary
    let object = try PropertyListSerialization.propertyList(from: data, options: [], format: &format)

    guard let root = dictionary(object) else {
        throw BookmarkError.invalidRoot
    }

    var entries: [SafariEntry] = []
    if readingList {
        collectReadingListEntries(from: root, path: [], inReadingList: false, entries: &entries)
    } else {
        collectBookmarkEntries(from: root, path: [], inReadingList: false, entries: &entries)
    }
    return entries
}

func writeJSON(_ entries: [SafariEntry]) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(entries)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

func humanText(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\r", with: " ")
        .replacingOccurrences(of: "\n", with: " ")
}

func writeHumanReadable(_ entries: [SafariEntry], readingList: Bool) {
    if entries.isEmpty {
        print(readingList ? "No Reading List entries found." : "No bookmarks found.")
        return
    }

    for entry in entries {
        let displayPath = readingList && !entry.path.isEmpty
            ? Array(entry.path.dropFirst())
            : entry.path
        let location = (displayPath + [entry.title]).map(humanText).joined(separator: " / ")
        print("- \(location)")
        print("  \(humanText(entry.url))")
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
var jsonOutput = false
var readingListOutput = false
var plistPath: String?

for argument in arguments {
    if argument == "--json" {
        jsonOutput = true
    } else if argument == "--reading-list" {
        readingListOutput = true
    } else if plistPath == nil {
        plistPath = argument
    } else {
        fail(BookmarkError.invalidArguments.localizedDescription)
    }
}

guard let plistPath = plistPath else {
    fail(BookmarkError.missingPath.localizedDescription)
}

do {
    let entries = try loadEntries(from: plistPath, readingList: readingListOutput)
    if jsonOutput {
        try writeJSON(entries)
    } else {
        writeHumanReadable(entries, readingList: readingListOutput)
    }
} catch {
    fail("could not read or parse '\(plistPath)': \(error.localizedDescription)")
}
