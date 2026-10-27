import Foundation

struct AudioTrack: Identifiable, Codable, Equatable {
    var id: UUID
    var fileName: String
    var title: String
    var artist: String
    var album: String
    var artworkData: Data?
    var videoID: String? = nil
    var artworkURL: URL? = nil
    var streamURL: URL? = nil
    var durationSeconds: Double? = nil
    var browseID: String? = nil

    var isOnline: Bool { videoID != nil }

    var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MumixicAudio", isDirectory: true)
            .appendingPathComponent(fileName)
    }
}

enum PlayerMode: String, CaseIterable, Identifiable {
    case classic = "Classic"
    case vinyl = "Vinyl"
    case coverFlow = "Cover Flow"

    var id: String { rawValue }
}
