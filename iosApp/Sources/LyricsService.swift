import Foundation

struct TimedLyric: Identifiable {
    let time: Double
    let text: String
    var id: Int { Int(time * 1000) }
}

enum LyricsService {
    private static let base = "https://lrclib.net/api"

    static func load(title: String, artist: String, duration: Double) async -> [TimedLyric] {
        guard let exactURL = makeURL(path: "get", items: [
            URLQueryItem(name: "track_name", value: clean(title)),
            URLQueryItem(name: "artist_name", value: clean(artist)),
            URLQueryItem(name: "duration", value: String(Int(duration)))
        ]) else { return [] }
        if let result = await fetch(exactURL), let lyrics = result["syncedLyrics"] as? String {
            let parsed = parse(lyrics)
            if !parsed.isEmpty { return parsed }
        }
        guard let searchURL = makeURL(path: "search", items: [
            URLQueryItem(name: "track_name", value: clean(title)),
            URLQueryItem(name: "artist_name", value: clean(artist))
        ]), let (data, _) = try? await URLSession.shared.data(from: searchURL),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        let candidates = rows.compactMap { row -> (Double, String)? in
            guard let text = row["syncedLyrics"] as? String, let seconds = row["duration"] as? Double else { return nil }
            return (seconds, text)
        }
        guard let best = candidates.min(by: { abs($0.0 - duration) < abs($1.0 - duration) }) else { return [] }
        return parse(best.1)
    }

    private static func fetch(_ url: URL) async -> [String: Any]? {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func makeURL(path: String, items: [URLQueryItem]) -> URL? {
        var components = URLComponents(string: "\(base)/\(path)")
        components?.queryItems = items
        return components?.url
    }

    private static func clean(_ value: String) -> String {
        value.replacingOccurrences(of: #"\s*\([^)]*\)\s*"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\|.*$"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func parse(_ source: String) -> [TimedLyric] {
        let regex = try? NSRegularExpression(pattern: #"\[(\d{1,2}):(\d{2})(?:\.(\d{2,3}))?\](.*)"#)
        return source.components(separatedBy: .newlines).compactMap { line in
            guard let regex, let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let minRange = Range(match.range(at: 1), in: line), let secRange = Range(match.range(at: 2), in: line),
                  let textRange = Range(match.range(at: 4), in: line), let minutes = Double(line[minRange]), let seconds = Double(line[secRange]) else { return nil }
            let fraction: Double
            if match.range(at: 3).location != NSNotFound, let range = Range(match.range(at: 3), in: line), let raw = Double(line[range]) {
                fraction = raw / (line[range].count == 2 ? 100 : 1000)
            } else { fraction = 0 }
            return TimedLyric(time: minutes * 60 + seconds + fraction, text: String(line[textRange]).trimmingCharacters(in: .whitespaces))
        }.sorted { $0.time < $1.time }
    }
}
