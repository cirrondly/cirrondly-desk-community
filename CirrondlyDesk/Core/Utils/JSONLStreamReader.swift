import Foundation

enum JSONLStreamReader {
    static func readObjects(at url: URL) async throws -> [[String: Any]] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var rows: [[String: Any]] = []
        for try await line in handle.bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard let data = trimmed.data(using: .utf8) else { continue }
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                rows.append(object)
            }
        }

        return rows
    }
}