import AVFoundation
import Foundation
import MediaPlayer
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class LocalPlayer: ObservableObject {
    @Published private(set) var tracks: [AudioTrack] = []
    @Published private(set) var currentTrackID: UUID?
    @Published private(set) var isPlaying = false
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0
    @Published var mode: PlayerMode = .coverFlow {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "mumixic.player-mode") }
    }
    @Published private(set) var isGoogleSignedIn = GoogleSessionStore.isSignedIn
    @Published private(set) var customBackgroundData: Data?
    @Published private(set) var onlineQueue: [AudioTrack] = []
    @Published private(set) var homeShelves: [HomeShelf] = []
    @Published private(set) var isLoadingHome = false
    @Published private(set) var homeLoadError: String?
    @Published private(set) var queue: [AudioTrack] = []
    @Published private(set) var playbackError: String?
    @Published private(set) var activeLyrics: [TimedLyric] = []
    private var remoteTrack: AudioTrack?
    private var lyricTask: Task<Void, Never>?
    private var remotePlaybackTask: Task<Void, Never>?
    private var lastHomeLoad: Date?

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    var currentIndex: Int? { tracks.firstIndex { $0.id == currentTrackID } }
    var currentTrack: AudioTrack? { remoteTrack ?? currentIndex.flatMap { tracks.indices.contains($0) ? tracks[$0] : nil } }
    var hasCustomBackground: Bool { customBackgroundData != nil }

    func searchOnline(_ query: String) async throws -> [AudioTrack] {
        let found = try await YtMusicService.search(query)
        onlineQueue = found
        return found
    }

    func loadHome(force: Bool = false) async {
        if !force, let lastHomeLoad, Date().timeIntervalSince(lastHomeLoad) < 300, !homeShelves.isEmpty { return }
        isLoadingHome = true; homeLoadError = nil
        do {
            homeShelves = try await YtMusicService.homeShelves()
            lastHomeLoad = Date()
        } catch { homeLoadError = error.localizedDescription }
        isLoadingHome = false
    }

    func playQueue(_ items: [AudioTrack], startingWith track: AudioTrack) {
        guard !items.isEmpty else { play(track); return }
        queue = items
        queueIndex = items.firstIndex(where: { identity($0) == identity(track) }) ?? 0
        play(queue[queueIndex])
    }

    func playHomeItem(_ item: AudioTrack, from shelf: [AudioTrack]) async {
        if item.isOnline {
            playQueue(shelf.filter(\.isOnline), startingWith: item)
        } else if let browseID = item.browseID {
            do {
                let songs = try await YtMusicService.playlistTracks(browseID: browseID)
                guard let first = songs.first else { playbackError = "This playlist has no playable songs."; return }
                playQueue(songs, startingWith: first)
            } catch { playbackError = error.localizedDescription }
        }
    }

    func enqueue(_ track: AudioTrack) {
        guard !queue.contains(where: { identity($0) == identity(track) }) else { return }
        queue.append(track)
    }

    func refreshAccountState() { isGoogleSignedIn = GoogleSessionStore.isSignedIn }

    func signOutGoogle() {
        GoogleSessionStore.clear()
        isGoogleSignedIn = false
        onlineQueue = []
        if remoteTrack != nil { player.pause(); player.replaceCurrentItem(with: nil); remoteTrack = nil; currentTrackID = nil; isPlaying = false }
    }

    func setCustomBackground(from source: URL) async {
        let hasAccess = source.startAccessingSecurityScopedResource()
        defer { if hasAccess { source.stopAccessingSecurityScopedResource() } }
        let ext = source.pathExtension.isEmpty ? "jpg" : source.pathExtension
        let name = "MumixicBackground.\(ext)"
        let destination = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(name)
        do {
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            try FileManager.default.copyItem(at: source, to: destination)
            customBackgroundData = try Data(contentsOf: destination)
            UserDefaults.standard.set(name, forKey: "mumixic.background-file")
        } catch { playbackError = "Could not save that background image." }
    }

    func removeCustomBackground() {
        if let name = UserDefaults.standard.string(forKey: "mumixic.background-file") {
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(name)
            try? FileManager.default.removeItem(at: url)
        }
        UserDefaults.standard.removeObject(forKey: "mumixic.background-file")
        customBackgroundData = nil
    }

    init() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session setup failed: \(error)")
        }
        restoreLibrary()
        if let raw = UserDefaults.standard.string(forKey: "mumixic.player-mode"), let restored = PlayerMode(rawValue: raw) { mode = restored }
        if let name = UserDefaults.standard.string(forKey: "mumixic.background-file") {
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(name)
            customBackgroundData = try? Data(contentsOf: url)
        }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.position = max(0, time.seconds.isFinite ? time.seconds : 0)
                let seconds = self.player.currentItem?.duration.seconds ?? 0
                self.duration = seconds.isFinite && seconds > 0 ? seconds : (self.currentTrack?.durationSeconds ?? 0)
                if let current = self.currentTrack, !self.activeLyrics.isEmpty {
                    // Timed lyric view observes position directly; no per-tick network work.
                    _ = current
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.skip(1) }
        }
        configureRemoteControls()
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    func importFiles(_ urls: [URL]) async {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MumixicAudio", isDirectory: true)
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { print("Could not create music folder: \(error)"); return }

        var added: [AudioTrack] = []
        for source in urls {
            let access = source.startAccessingSecurityScopedResource()
            defer { if access { source.stopAccessingSecurityScopedResource() } }
            let base = source.deletingPathExtension().lastPathComponent
            let ext = source.pathExtension.isEmpty ? "m4a" : source.pathExtension
            let destination = directory.appendingPathComponent("\(UUID().uuidString)-\(base).\(ext)")
            do {
                try FileManager.default.copyItem(at: source, to: destination)
                let asset = AVURLAsset(url: destination)
                let metadata = (try? await asset.load(.commonMetadata)) ?? []
                let title = await Self.stringValue(.commonIdentifierTitle, in: metadata) ?? base
                let artist = await Self.stringValue(.commonIdentifierArtist, in: metadata) ?? "Unknown artist"
                let album = await Self.stringValue(.commonIdentifierAlbumName, in: metadata) ?? "Local music"
                let artworkItem = AVMetadataItem.metadataItems(
                    from: metadata,
                    filteredByIdentifier: .commonIdentifierArtwork
                ).first
                let artwork = try? await artworkItem?.load(.dataValue)
                added.append(AudioTrack(
                    id: UUID(),
                    fileName: destination.lastPathComponent,
                    title: title,
                    artist: artist,
                    album: album,
                    artworkData: artwork ?? nil
                ))
            } catch {
                print("Could not import \(source.lastPathComponent): \(error)")
            }
        }
        tracks.append(contentsOf: added)
        saveLibrary()
        if currentTrackID == nil, let first = tracks.first { play(first) }
    }

    func play(_ track: AudioTrack) {
        if track.isOnline {
            if let index = queue.firstIndex(where: { identity($0) == identity(track) }) { queueIndex = index }
            else if let index = onlineQueue.firstIndex(where: { identity($0) == identity(track) }) { queue = onlineQueue; queueIndex = index }
            else { queue = [track]; queueIndex = 0 }
            remoteTrack = track
            currentTrackID = nil
            playbackError = nil
            activeLyrics = []
            player.pause()
            isPlaying = false
            lyricTask?.cancel()
            remotePlaybackTask?.cancel()
            remotePlaybackTask = Task { [weak self] in
                guard let self else { return }
                do {
                    guard let videoID = track.videoID else { return }
                    let url: URL
                    if let cached = track.streamURL { url = cached }
                    else { url = try await YtMusicService.resolveStream(videoID: videoID) }
                    guard !Task.isCancelled else { return }
                    let item = AVPlayerItem(url: url)
                    self.player.replaceCurrentItem(with: item)
                    self.player.play()
                    self.isPlaying = true
                    self.updateNowPlayingInfo()
                    if let artworkURL = track.artworkURL,
                       let (imageData, _) = try? await URLSession.shared.data(from: artworkURL),
                       var updated = self.remoteTrack, updated.videoID == track.videoID {
                        updated.artworkData = imageData
                        self.remoteTrack = updated
                        self.updateNowPlayingInfo()
                    }
                } catch {
                    self.isPlaying = false
                    self.playbackError = error.localizedDescription
                }
            }
            lyricTask = Task { [weak self] in
                let lines = await LyricsService.load(title: track.title, artist: track.artist, duration: track.durationSeconds ?? 0)
                guard !Task.isCancelled else { return }
                self?.activeLyrics = lines
            }
            return
        }
        guard FileManager.default.fileExists(atPath: track.fileURL.path) else { return }
        if let index = queue.firstIndex(where: { identity($0) == identity(track) }) { queueIndex = index }
        else { queue = tracks; queueIndex = tracks.firstIndex(where: { $0.id == track.id }) ?? 0 }
        remotePlaybackTask?.cancel()
        lyricTask?.cancel()
        remoteTrack = nil
        playbackError = nil
        activeLyrics = []
        currentTrackID = track.id
        position = 0
        let item = AVPlayerItem(url: track.fileURL)
        player.replaceCurrentItem(with: item)
        player.play()
        isPlaying = true
        updateNowPlayingInfo()
    }

    func togglePlayback() {
        if isPlaying { player.pause(); isPlaying = false }
        else if player.currentItem != nil { player.play(); isPlaying = true }
        else if let first = queue.indices.contains(queueIndex) ? queue[queueIndex] : (remoteTrack == nil ? tracks.first : onlineQueue.first) { play(first) }
        updateNowPlayingInfo()
    }

    func skip(_ amount: Int) {
        if !queue.isEmpty {
            let next = (queueIndex + amount % queue.count + queue.count) % queue.count
            queueIndex = next
            play(queue[next]); return
        }
        guard !tracks.isEmpty else { return }
        let index = currentIndex ?? 0
        let next = (index + amount % tracks.count + tracks.count) % tracks.count
        play(tracks[next])
    }

    private var queueIndex = 0
    private func identity(_ track: AudioTrack) -> String { track.videoID ?? track.id.uuidString }

    func seek(to seconds: Double) {
        let safe = max(0, min(seconds, max(duration, 0)))
        player.seek(to: CMTime(seconds: safe, preferredTimescale: 600))
        position = safe
        updateNowPlayingInfo()
    }

    func remove(_ track: AudioTrack) {
        tracks.removeAll { $0.id == track.id }
        try? FileManager.default.removeItem(at: track.fileURL)
        if currentTrackID == track.id {
            player.pause()
            isPlaying = false
            currentTrackID = nil
            if let next = tracks.first { play(next) }
        }
        saveLibrary()
    }

    private static func stringValue(_ identifier: AVMetadataIdentifier, in metadata: [AVMetadataItem]) async -> String? {
        guard let item = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: identifier).first else { return nil }
        return try? await item.load(.stringValue)
    }

    private func restoreLibrary() {
        guard let data = UserDefaults.standard.data(forKey: "mumixic.local-library"),
              let saved = try? JSONDecoder().decode([AudioTrack].self, from: data) else { return }
        tracks = saved.filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }
        saveLibrary()
    }

    private func saveLibrary() {
        guard let data = try? JSONEncoder().encode(tracks) else { return }
        UserDefaults.standard.set(data, forKey: "mumixic.local-library")
    }

    private func configureRemoteControls() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayback() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayback() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skip(1) }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skip(-1) }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let data = track.artworkData, let image = UIImage(data: data) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
