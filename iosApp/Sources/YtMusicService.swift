import Foundation
import CryptoKit

/// Small, native YouTube Music client for anonymous song search and playback.
/// YouTube can require an integrity token for some tracks; those are reported
/// clearly instead of silently falling back to a broken player.
enum YtMusicService {
    private static let origin = "https://music.youtube.com"
    private static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36"
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    static func search(_ query: String) async throws -> [AudioTrack] {
        let page = try await get(URL(string: origin)!)
        let html = String(decoding: page, as: UTF8.self)
        guard let apiKey = capture(#""INNERTUBE_API_KEY":"([^"]+)""#, in: html),
              let version = capture(#""INNERTUBE_CLIENT_VERSION":"([^"]+)""#, in: html) else {
            throw ServiceError.unavailable("YouTube Music did not return its public client configuration. Try again later.")
        }
        let visitor = capture(#""VISITOR_DATA":"([^"]+)""#, in: html)
        let endpoint = URL(string: "\(origin)/youtubei/v1/search?key=\(apiKey)&prettyPrint=false")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(origin, forHTTPHeaderField: "Origin")
        request.setValue(origin, forHTTPHeaderField: "X-Origin")
        request.setValue("\(origin)/", forHTTPHeaderField: "Referer")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("67", forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(version, forHTTPHeaderField: "X-YouTube-Client-Version")
        if let visitor { request.setValue(visitor, forHTTPHeaderField: "X-Goog-Visitor-Id") }
        authorize(&request)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "context": [
                "client": ["clientName": "WEB_REMIX", "clientVersion": version, "hl": "en", "gl": "US", "visitorData": visitor as Any? ?? NSNull()],
                "user": ["lockedSafetyMode": false],
                "request": ["useSsl": true]
            ],
            "query": query,
            "params": "EgWKAQIIAWoKEAkQChAFEAMQBA=="
        ])
        let data = try await send(request)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var tracks: [AudioTrack] = []
        var seen = Set<String>()
        walk(root) { object in
            guard let renderer = object["musicResponsiveListItemRenderer"] as? [String: Any],
                  let track = parseSongRow(renderer), !seen.contains(track.videoID ?? "") else { return }
            seen.insert(track.videoID ?? "")
            tracks.append(track)
        }
        return Array(tracks.prefix(40))
    }

    static func homeShelves() async throws -> [HomeShelf] {
        let config = try await clientConfig()
        var request = makeRequest(path: "browse", apiKey: config.key)
        request.setValue(config.version, forHTTPHeaderField: "X-YouTube-Client-Version")
        if let visitor = config.visitor { request.setValue(visitor, forHTTPHeaderField: "X-Goog-Visitor-Id") }
        authorize(&request)
        var client: [String: Any] = ["clientName": "WEB_REMIX", "clientVersion": config.version, "hl": "en", "gl": "US"]
        if let visitor = config.visitor { client["visitorData"] = visitor }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "context": ["client": client, "user": ["lockedSafetyMode": false], "request": ["useSsl": true]],
            "browseId": "FEmusic_home"
        ])
        let data = try await send(request)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let contents = (((root["contents"] as? [String: Any])?["singleColumnBrowseResultsRenderer"] as? [String: Any])?["tabs"] as? [[String: Any]])?.first
            .flatMap { ($0["tabRenderer"] as? [String: Any])? ["content"] as? [String: Any] }
            .flatMap { ($0["sectionListRenderer"] as? [String: Any])? ["contents"] as? [[String: Any] ] } ?? []
        return contents.compactMap { section in
            guard let shelf = (section["musicCarouselShelfRenderer"] as? [String: Any]) ?? (section["musicShelfRenderer"] as? [String: Any]) else { return nil }
            let header = shelf["header"] as? [String: Any] ?? [:]
            let headerRenderer = (header["musicCarouselShelfBasicHeaderRenderer"] as? [String: Any])
                ?? (header["musicShelfHeaderRenderer"] as? [String: Any]) ?? header
            guard let title = text(in: headerRenderer["title"]), !title.isEmpty else { return nil }
            let rows = (shelf["contents"] as? [[String: Any]]) ?? (shelf["items"] as? [[String: Any]]) ?? []
            var cards: [AudioTrack] = []
            var seen = Set<String>()
            for row in rows {
                walk(row) { object in
                    if let renderer = object["musicResponsiveListItemRenderer"] as? [String: Any],
                       let track = parseSongRow(renderer), let key = track.videoID, seen.insert(key).inserted {
                        cards.append(track)
                    } else if let renderer = object["musicTwoRowItemRenderer"] as? [String: Any],
                              let card = parseBrowseCard(renderer), let key = card.browseID, seen.insert(key).inserted {
                        cards.append(card)
                    }
                }
            }
            return cards.isEmpty ? nil : HomeShelf(title: title, items: cards)
        }
    }

    static func playlistTracks(browseID: String) async throws -> [AudioTrack] {
        let config = try await clientConfig()
        var request = makeRequest(path: "browse", apiKey: config.key)
        request.setValue(config.version, forHTTPHeaderField: "X-YouTube-Client-Version")
        if let visitor = config.visitor { request.setValue(visitor, forHTTPHeaderField: "X-Goog-Visitor-Id") }
        authorize(&request)
        var client: [String: Any] = ["clientName": "WEB_REMIX", "clientVersion": config.version, "hl": "en", "gl": "US"]
        if let visitor = config.visitor { client["visitorData"] = visitor }
        let id = browseID.hasPrefix("VL") ? browseID : "VL\(browseID)"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["context": ["client": client, "user": ["lockedSafetyMode": false], "request": ["useSsl": true]], "browseId": id])
        let data = try await send(request)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var result: [AudioTrack] = []; var seen = Set<String>()
        walk(root) { object in
            guard let renderer = object["musicResponsiveListItemRenderer"] as? [String: Any],
                  let track = parseSongRow(renderer), let id = track.videoID, seen.insert(id).inserted else { return }
            result.append(track)
        }
        return result
    }

    private struct ClientConfig { let key: String; let version: String; let visitor: String? }

    private static func clientConfig() async throws -> ClientConfig {
        let page = try await get(URL(string: origin)!)
        let html = String(decoding: page, as: UTF8.self)
        guard let key = capture(#""INNERTUBE_API_KEY"\s*:\s*"([^"]+)""#, in: html),
              let version = capture(#""INNERTUBE_CLIENT_VERSION"\s*:\s*"([^"]+)""#, in: html) else {
            throw ServiceError.unavailable("YouTube Music did not return its public client configuration. Try again later.")
        }
        return ClientConfig(key: key, version: version, visitor: capture(#""VISITOR_DATA"\s*:\s*"([^"]+)""#, in: html))
    }

    private static func makeRequest(path: String, apiKey: String) -> URLRequest {
        let endpoint = URL(string: "\(origin)/youtubei/v1/\(path)?key=\(apiKey)&prettyPrint=false")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(origin, forHTTPHeaderField: "Origin")
        request.setValue(origin, forHTTPHeaderField: "X-Origin")
        request.setValue("\(origin)/", forHTTPHeaderField: "Referer")
        request.setValue("67", forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        return request
    }

    private static func parseBrowseCard(_ renderer: [String: Any]) -> AudioTrack? {
        guard let title = text(in: renderer["title"]), !title.isEmpty else { return nil }
        let browse = deepString(key: "browseId", in: renderer)
        let video = browse == nil ? deepString(key: "videoId", in: renderer) : nil
        guard browse != nil || video != nil else { return nil }
        let subtitle = text(in: renderer["subtitle"]) ?? "YouTube Music"
        return AudioTrack(id: UUID(), fileName: "", title: title, artist: subtitle, album: "YouTube Music", artworkData: nil,
                          videoID: video, artworkURL: thumbnail(in: renderer["thumbnailRenderer"] ?? renderer["thumbnail"]),
                          streamURL: nil, durationSeconds: nil, browseID: browse)
    }

    private static func deepString(key: String, in value: Any) -> String? {
        if let object = value as? [String: Any] {
            if let found = object[key] as? String { return found }
            for child in object.values { if let found = deepString(key: key, in: child) { return found } }
        } else if let array = value as? [Any] {
            for child in array { if let found = deepString(key: key, in: child) { return found } }
        }
        return nil
    }

    static func resolveStream(videoID: String) async throws -> URL {
        let page = try await get(URL(string: origin)!)
        let html = String(decoding: page, as: UTF8.self)
        guard let apiKey = capture(#""INNERTUBE_API_KEY":"([^"]+)""#, in: html),
              let version = capture(#""INNERTUBE_CLIENT_VERSION":"([^"]+)""#, in: html) else {
            throw ServiceError.unavailable("Could not initialize YouTube Music playback.")
        }
        let endpoint = URL(string: "\(origin)/youtubei/v1/player?key=\(apiKey)&prettyPrint=false")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(origin, forHTTPHeaderField: "Origin")
        request.setValue(origin, forHTTPHeaderField: "X-Origin")
        request.setValue("\(origin)/", forHTTPHeaderField: "Referer")
        request.setValue("67", forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(version, forHTTPHeaderField: "X-YouTube-Client-Version")
        authorize(&request)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "context": ["client": ["clientName": "WEB_REMIX", "clientVersion": version, "hl": "en", "gl": "US"], "user": ["lockedSafetyMode": false], "request": ["useSsl": true]],
            "videoId": videoID, "contentCheckOk": true, "racyCheckOk": true
        ])
        let data = try await send(request)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ServiceError.unavailable("Unexpected player response.") }
        let streaming = root["streamingData"] as? [String: Any]
        if let formats = streaming?["adaptiveFormats"] as? [[String: Any]],
           let urlString = formats.first(where: { ($0["mimeType"] as? String)?.hasPrefix("audio/") == true })?["url"] as? String,
           let url = URL(string: urlString) { return url }
        if let reason = (root["playabilityStatus"] as? [String: Any])?["reason"] as? String {
            throw ServiceError.unavailable("YouTube cannot play this track here: \(reason)")
        }
        throw ServiceError.unavailable("YouTube requires a playback integrity token for this track. Try another result.")
    }

    private static func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return try await send(request)
    }

    private static func parseSongRow(_ renderer: [String: Any]) -> AudioTrack? {
        let overlayID = (((renderer["overlay"] as? [String: Any])?["musicItemThumbnailOverlayRenderer"] as? [String: Any])?["content"] as? [String: Any])
            .flatMap { ($0["musicPlayButtonRenderer"] as? [String: Any])? ["playNavigationEndpoint"] as? [String: Any] }
            .flatMap { ($0["watchEndpoint"] as? [String: Any])? ["videoId"] as? String }
        let videoID = (renderer["playlistItemData"] as? [String: Any])?["videoId"] as? String
            ?? overlayID
            ?? ((renderer["navigationEndpoint"] as? [String: Any])?["watchEndpoint"] as? [String: Any])?["videoId"] as? String
        guard let videoID, videoID.count == 11,
              let columns = renderer["flexColumns"] as? [[String: Any]], !columns.isEmpty,
              let firstColumn = columns[0]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
              let title = text(in: firstColumn["text"]), !title.isEmpty else { return nil }

        let subtitle = columns.dropFirst().compactMap { column -> String? in
            guard let renderer = column["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any] else { return nil }
            return text(in: renderer["text"])
        }.joined(separator: " • ")
        let parts = subtitle.components(separatedBy: " • ").filter { !$0.isEmpty }
        let artist = parts.first(where: { parseDuration($0) == nil && !$0.localizedCaseInsensitiveContains("song") && !$0.localizedCaseInsensitiveContains("video") }) ?? "YouTube Music"
        let durationText = parts.last(where: { parseDuration($0) != nil })
            ?? (renderer["fixedColumns"] as? [[String: Any]])?.compactMap { column -> String? in
                guard let fixed = column["musicResponsiveListItemFixedColumnRenderer"] as? [String: Any] else { return nil }
                return text(in: fixed["text"])
            }.first(where: { parseDuration($0) != nil })
        return AudioTrack(id: UUID(), fileName: "", title: title, artist: artist, album: "YouTube Music", artworkData: nil,
                          videoID: videoID, artworkURL: thumbnail(in: renderer["thumbnail"]), streamURL: nil,
                          durationSeconds: durationText.flatMap(parseDuration))
    }

    private static func authorize(_ request: inout URLRequest) {
        guard let cookie = GoogleSessionStore.cookie else { return }
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("0", forHTTPHeaderField: "X-Goog-AuthUser")
        let values = Dictionary(cookie.split(separator: ";").compactMap { entry -> (String, String)? in
            let fields = entry.split(separator: "=", maxSplits: 1)
            guard fields.count == 2 else { return nil }
            return (fields[0].trimmingCharacters(in: .whitespaces), fields[1].trimmingCharacters(in: .whitespaces))
        }, uniquingKeysWith: { _, latest in latest })
        let secret = values["SAPISID"] ?? values["__Secure-3PAPISID"] ?? values["__Secure-1PAPISID"]
        guard let secret else { return }
        let timestamp = Int(Date().timeIntervalSince1970)
        let digest = Insecure.SHA1.hash(data: Data("\(timestamp) \(secret) \(origin)".utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        request.setValue("SAPISIDHASH \(timestamp)_\(hex)", forHTTPHeaderField: "Authorization")
    }

    private static func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ServiceError.unavailable("YouTube Music request failed. Check your connection and try again.")
        }
        return data
    }

    private static func capture(_ pattern: String, in input: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)),
              let range = Range(match.range(at: 1), in: input) else { return nil }
        return String(input[range])
    }

    private static func walk(_ value: Any, visit: ([String: Any]) -> Void) {
        if let object = value as? [String: Any] {
            visit(object)
            object.values.forEach { walk($0, visit: visit) }
        } else if let array = value as? [Any] { array.forEach { walk($0, visit: visit) } }
    }

    private static func text(in value: Any?) -> String? {
        guard let object = value as? [String: Any] else { return nil }
        if let simple = object["simpleText"] as? String { return simple }
        if let runs = object["runs"] as? [[String: Any]] {
            let result = runs.compactMap { $0["text"] as? String }.joined()
            return result.isEmpty ? nil : result
        }
        if let nestedText = object["text"] { return text(in: nestedText) }
        if let renderer = object["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any] { return text(in: renderer["text"]) }
        return nil
    }

    private static func thumbnail(in value: Any?) -> URL? {
        guard let object = value as? [String: Any], let details = object["musicThumbnailRenderer"] as? [String: Any],
              let thumbnail = details["thumbnail"] as? [String: Any], let items = thumbnail["thumbnails"] as? [[String: Any]],
              let string = items.last?["url"] as? String else { return nil }
        return URL(string: string)
    }

    private static func parseDuration(_ value: String) -> Double? {
        let parts = value.split(separator: ":").compactMap { Double($0) }
        guard !parts.isEmpty else { return nil }
        return parts.reversed().enumerated().reduce(0) { $0 + $1.element * pow(60, Double($1.offset)) }
    }

    enum ServiceError: LocalizedError {
        case unavailable(String)
        var errorDescription: String? { if case let .unavailable(message) = self { return message }; return nil }
    }
}
