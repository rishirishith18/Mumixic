import AVFoundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@main
struct MumixicApp: App {
    @StateObject private var player = LocalPlayer()

    var body: some Scene {
        WindowGroup {
            MumixicRootView()
                .environmentObject(player)
                .tint(Color(red: 0.78, green: 0.62, blue: 0.88))
        }
    }
}

private enum MainTab: Int, CaseIterable {
    case home, library, search, settings

    var title: String {
        switch self {
        case .home: "Home"
        case .library: "Library"
        case .search: "Search"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .library: "square.grid.2x2.fill"
        case .search: "magnifyingglass"
        case .settings: "gearshape.fill"
        }
    }
}

struct MumixicRootView: View {
    @EnvironmentObject private var player: LocalPlayer
    @State private var tab: MainTab = .home
    @State private var showPlayer = false
    @State private var showImporter = false
    @State private var showBackgroundImporter = false
    @State private var showGoogleLogin = false
    @State private var tabTransitionEdge: Edge = .trailing
    @AppStorage("mumixic.theme") private var theme = "Dark"

    var body: some View {
        ZStack {
            Group {
                switch tab {
                case .home: HomeScreen(openLibrary: { switchTab(.library) }, importMusic: { showImporter = true })
                case .library: LibraryScreen(importMusic: { showImporter = true }, openPlayer: { showPlayer = true })
                case .search: SearchScreen(openPlayer: { showPlayer = true })
                case .settings: SettingsScreen(showGoogleLogin: { showGoogleLogin = true }, chooseBackground: { showBackgroundImporter = true })
                }
            }
            .id(tab)
            .transition(.asymmetric(
                insertion: .move(edge: tabTransitionEdge).combined(with: .opacity),
                removal: .opacity
            ))
            .contentShape(Rectangle())
            .simultaneousGesture(DragGesture(minimumDistance: 48).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.2 else { return }
                let next = tab.rawValue + (value.translation.width < 0 ? 1 : -1)
                if let destination = MainTab(rawValue: min(max(next, 0), MainTab.allCases.count - 1)) {
                    switchTab(destination)
                }
            })
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .preferredColorScheme(theme == "System" ? nil : (theme == "Light" ? .light : .dark))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 9) {
                if player.currentTrack != nil {
                    MiniPlayer(openPlayer: { showPlayer = true })
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                MainDock(selected: $tab, onSelect: switchTab)
            }
            .padding(.horizontal, 15)
            .padding(.bottom, 7)
            .animation(.spring(response: 0.38, dampingFraction: 0.86), value: player.currentTrack?.id)
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true,
            onCompletion: { result in
                guard case let .success(urls) = result else { return }
                Task { await player.importFiles(urls) }
            }
        )
        .fileImporter(isPresented: $showBackgroundImporter, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            Task { @MainActor in await player.setCustomBackground(from: url) }
        }
        .fullScreenCover(isPresented: $showGoogleLogin) {
            GoogleLoginView(onSignedIn: { player.refreshAccountState() })
        }
        .fullScreenCover(isPresented: $showPlayer) {
            NowPlayingScreen().environmentObject(player)
        }
    }

    private func switchTab(_ destination: MainTab) {
        guard destination != tab else { return }
        tabTransitionEdge = destination.rawValue > tab.rawValue ? .trailing : .leading
        withAnimation(.spring(response: 0.36, dampingFraction: 0.9)) { tab = destination }
    }
}

private struct HomeScreen: View {
    @EnvironmentObject private var player: LocalPlayer
    let openLibrary: () -> Void
    let importMusic: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 27) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MUMIXIC").font(.caption.weight(.bold)).tracking(2.5).foregroundStyle(.secondary)
                        Text("HOME").font(.system(size: 48, weight: .black, design: .rounded)).tracking(-2)
                    }
                    Spacer()
                    Button { Task { await player.loadHome(force: true) } } label: {
                        if player.isLoadingHome { ProgressView().tint(.primary).frame(width: 42, height: 42) }
                        else { Image(systemName: "arrow.clockwise").font(.title3.weight(.semibold)).frame(width: 42, height: 42) }
                    }
                    Button(action: importMusic) {
                        Image(systemName: "plus").font(.title3.weight(.semibold))
                            .frame(width: 48, height: 48)
                            .background(.white.opacity(0.11), in: Circle())
                    }
                    .accessibilityLabel("Add music")
                }
                if player.isLoadingHome && player.homeShelves.isEmpty {
                    ProgressView("Loading your music").frame(maxWidth: .infinity).padding(.vertical, 34)
                }
                if !player.homeShelves.isEmpty {
                    ForEach(player.homeShelves) { shelf in
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeading(title: shelf.title, action: "Queue", onAction: {
                                guard let first = shelf.items.first(where: \.isOnline) else { return }
                                player.playQueue(shelf.items.filter(\.isOnline), startingWith: first)
                            })
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: 14) {
                                    ForEach(shelf.items) { item in
                                        Button { Task { await player.playHomeItem(item, from: shelf.items) } } label: {
                                            VStack(alignment: .leading, spacing: 8) {
                                                TrackArtwork(track: item).frame(width: 154, height: 154).clipShape(RoundedRectangle(cornerRadius: 15))
                                                Text(item.title).font(.headline).lineLimit(1)
                                                Text(item.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                            }
                                            .frame(width: 154, alignment: .leading)
                                        }.buttonStyle(.plain)
                                        .contextMenu {
                                            if item.isOnline { Button { player.enqueue(item) } label: { Label("Add to queue", systemImage: "text.badge.plus") } }
                                        }
                                    }
                                }
                            }
                        }
                    }
                } else if let error = player.homeLoadError {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                    EmptyLibraryCard(importMusic: importMusic, openLibrary: openLibrary)
                } else {
                    EmptyLibraryCard(importMusic: importMusic, openLibrary: openLibrary)
                }
                if !player.tracks.isEmpty {
                    VStack(alignment: .leading, spacing: 11) {
                        SectionHeading(title: "Recently added", action: "Library", onAction: openLibrary)
                        ForEach(player.tracks.suffix(5).reversed()) { track in
                            TrackRow(track: track) { player.play(track) }
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 22)
        }
        .task { await player.loadHome() }
    }
}

private struct EmptyLibraryCard: View {
    let importMusic: () -> Void
    let openLibrary: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            ZStack {
                RoundedRectangle(cornerRadius: 24).fill(
                    LinearGradient(colors: [Color(red: 0.27, green: 0.14, blue: 0.42), Color(red: 0.09, green: 0.13, blue: 0.31)], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                Image(systemName: "waveform").font(.system(size: 58, weight: .light)).foregroundStyle(.white.opacity(0.9))
            }
            .frame(height: 260)
            Text("Your music, your way").font(.title2.bold())
            Text("Add audio from Files to start building your Mumixic library.")
                .font(.body).foregroundStyle(.secondary)
            Button(action: importMusic) {
                Label("Import music", systemImage: "plus").font(.headline)
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(.white, in: Capsule()).foregroundStyle(.black)
            }
            Button("Browse library") { openLibrary() }.frame(maxWidth: .infinity).foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 26))
    }
}

private struct LibraryScreen: View {
    @EnvironmentObject private var player: LocalPlayer
    let importMusic: () -> Void
    let openPlayer: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 21) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("YOUR COLLECTION").font(.caption.weight(.bold)).tracking(2).foregroundStyle(.secondary)
                        Text("Library").font(.system(size: 42, weight: .bold, design: .rounded))
                    }
                    Spacer()
                    Button(action: importMusic) { Image(systemName: "plus.circle.fill").font(.system(size: 31)) }
                        .accessibilityLabel("Import audio files")
                }
                if player.tracks.isEmpty {
                    ContentUnavailableView("No music yet", systemImage: "music.note.list", description: Text("Import songs from the Files app."))
                        .frame(maxWidth: .infinity).padding(.top, 60)
                } else {
                    Text("SONGS  ·  \(player.tracks.count)").font(.caption.weight(.bold)).tracking(1.5).foregroundStyle(.secondary)
                    ForEach(player.tracks) { track in
                        TrackRow(track: track) { player.play(track); openPlayer() }
                            .contextMenu { Button(role: .destructive) { player.remove(track) } label: { Label("Remove from library", systemImage: "trash") } }
                    }
                }
            }
            .padding(.horizontal, 22).padding(.top, 24).padding(.bottom, 24)
        }
    }
}

private struct SearchScreen: View {
    @EnvironmentObject private var player: LocalPlayer
    @State private var query = ""
    @State private var onlineResults: [AudioTrack] = []
    @State private var onlineError: String?
    @State private var isSearchingOnline = false
    @State private var didSearchOnline = false
    let openPlayer: () -> Void

    private var results: [AudioTrack] {
        guard !query.isEmpty else { return player.tracks }
        return player.tracks.filter { "\($0.title) \($0.artist) \($0.album)".localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Search").font(.system(size: 42, weight: .bold, design: .rounded)).padding(.horizontal, 22).padding(.top, 24)
            HStack(spacing: 11) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Songs, artists, albums", text: $query)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.search).onSubmit { Task { await searchOnline() } }
            }
            .padding(15).background(.white.opacity(0.085), in: RoundedRectangle(cornerRadius: 15)).padding(.horizontal, 20)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("YOUTUBE MUSIC").font(.caption.weight(.bold)).tracking(1.5).foregroundStyle(.secondary)
                            Spacer()
                            if isSearchingOnline { ProgressView().tint(.white) }
                            else { Button("Search online") { Task { await searchOnline() } }.font(.caption.weight(.semibold)) }
                        }
                        if let onlineError { Text(onlineError).font(.footnote).foregroundStyle(.orange) }
                        ForEach(onlineResults) { track in
                            TrackRow(track: track) { player.playQueue(onlineResults, startingWith: track); openPlayer() }
                                .contextMenu { Button { player.enqueue(track) } label: { Label("Add to queue", systemImage: "text.badge.plus") } }
                        }
                        if onlineResults.isEmpty && !isSearchingOnline && onlineError == nil {
                            Text(didSearchOnline ? "No songs found. Try a different title or artist." : "Search YouTube Music for songs and artists.")
                                .font(.footnote).foregroundStyle(.secondary).padding(.vertical, 4)
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ON THIS IPHONE").font(.caption.weight(.bold)).tracking(1.5).foregroundStyle(.secondary)
                        ForEach(results) { track in TrackRow(track: track) { player.play(track); openPlayer() } }
                        if results.isEmpty { Text("Import audio from Files to build your offline library.").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 8) }
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 20)
            }
            Spacer(minLength: 0)
        }
    }

    @MainActor private func searchOnline() async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearchingOnline = true; onlineError = nil; onlineResults = []
        do { onlineResults = try await player.searchOnline(query); didSearchOnline = true }
        catch { onlineError = error.localizedDescription }
        isSearchingOnline = false
    }
}

private struct SettingsScreen: View {
    @EnvironmentObject private var player: LocalPlayer
    @AppStorage("mumixic.theme") private var theme = "Dark"
    @AppStorage("mumixic.show-lyrics") private var showLyrics = true
    @State private var showSignOutConfirmation = false
    let showGoogleLogin: () -> Void
    let chooseBackground: () -> Void

    var body: some View {
        Form {
            Section {
                Picker("Now playing style", selection: $player.mode) {
                    ForEach(PlayerMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                }
                .pickerStyle(.navigationLink)
            } header: { Text("PLAYER") } footer: { Text("Choose the artwork style used on the Now Playing screen.") }
            Section("APPEARANCE") {
                Picker("Theme", selection: $theme) {
                    Text("System").tag("System"); Text("Light").tag("Light"); Text("Dark").tag("Dark")
                }
                Button { chooseBackground() } label: { Label("Custom player background", systemImage: "photo") }
                if player.hasCustomBackground {
                    Button("Remove custom background", role: .destructive) { player.removeCustomBackground() }
                }
            }
            Section("LYRICS") {
                Toggle("Show synchronized lyrics", isOn: $showLyrics)
                Text("Timed lyrics appear during playback when LRCLIB has a synchronized version.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("YOUTUBE MUSIC ACCOUNT") {
                if player.isGoogleSignedIn {
                    Label("Signed in to YouTube Music", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Button("Sign out", role: .destructive) { showSignOutConfirmation = true }
                        .confirmationDialog("Sign out of YouTube Music?", isPresented: $showSignOutConfirmation, titleVisibility: .visible) {
                            Button("Sign out", role: .destructive) { player.signOutGoogle() }
                        }
                } else {
                    Button(action: showGoogleLogin) { Label("Sign in with Google", systemImage: "person.crop.circle.badge.checkmark") }
                    Text("Sign in to connect YouTube Music. Your session is stored on this iPhone in Keychain.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("YOUR LIBRARY") {
                LabeledContent("On this iPhone", value: "\(player.tracks.count) songs")
                Text("Import audio in MP3, AAC, M4A, WAV, or other iPhone-supported formats from Files.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("ABOUT") {
                LabeledContent("App", value: "Mumixic for iPhone")
                LabeledContent("Version", value: "1.0")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemBackground))
    }
}

private struct NowPlayingScreen: View {
    @EnvironmentObject private var player: LocalPlayer
    @Environment(\.dismiss) private var dismiss
    @State private var scrubValue = 0.0
    @State private var isScrubbing = false
    @State private var showQueue = false
    @AppStorage("mumixic.show-lyrics") private var showLyrics = true

    private var track: AudioTrack? { player.currentTrack }
    private var backgroundImage: UIImage? {
        track?.artworkData.flatMap(UIImage.init(data:)) ?? player.customBackgroundData.flatMap(UIImage.init(data:))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                PlayerBackdrop(image: backgroundImage)
                VStack(spacing: 0) {
                    Capsule().fill(.white.opacity(0.55)).frame(width: 42, height: 5).padding(.top, 10)
                    HStack {
                        Button { dismiss() } label: { Image(systemName: "chevron.down").font(.title3.weight(.semibold)).frame(width: 44, height: 44) }
                        Spacer()
                        VStack(spacing: 3) {
                            Text("PLAYING FROM").font(.system(size: 9, weight: .bold)).tracking(1.8).foregroundStyle(.secondary)
                            Text(track?.album ?? "Your library").font(.subheadline.weight(.semibold)).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "ellipsis").font(.title3.weight(.semibold)).frame(width: 44, height: 44)
                    }
                    .padding(.horizontal, 16).padding(.top, 12)

                    Spacer(minLength: 10)
                    Group {
                        switch player.mode {
                        case .classic:
                            AnimatedCoverArtwork(track: track, isPlaying: player.isPlaying).clipShape(RoundedRectangle(cornerRadius: 19))
                                .shadow(color: .black.opacity(0.3), radius: 24, y: 16)
                        case .vinyl:
                            VinylArtwork(track: track, isPlaying: player.isPlaying)
                        case .coverFlow:
                            CoverFlowArtwork()
                        }
                    }
                    .frame(width: min(geometry.size.width - 42, geometry.size.height * 0.40), height: min(geometry.size.width - 42, geometry.size.height * 0.40))
                    .frame(maxWidth: .infinity)
                    .gesture(DragGesture(minimumDistance: 35).onEnded { value in
                        if value.translation.width < -45 { player.skip(1) }
                        else if value.translation.width > 45 { player.skip(-1) }
                    })

                    Spacer(minLength: 20)
                    HStack(alignment: .center, spacing: 14) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(track?.title ?? "Nothing playing").font(.title2.bold()).lineLimit(1)
                            Text(track?.artist ?? "Import music from Files").font(.title3).foregroundStyle(.white.opacity(0.68)).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Menu {
                            Section("Now Playing Style") {
                                ForEach(PlayerMode.allCases) { mode in
                                    Button { player.mode = mode } label: {
                                        if player.mode == mode { Label(mode.rawValue, systemImage: "checkmark") }
                                        else { Text(mode.rawValue) }
                                    }
                                }
                            }
                            Toggle("Synchronized lyrics", isOn: $showLyrics)
                        } label: {
                            Image(systemName: "ellipsis.circle.fill").font(.system(size: 36)).foregroundStyle(.white.opacity(0.72))
                        }
                    }
                    .padding(.horizontal, 25)

                    if showLyrics && !player.activeLyrics.isEmpty {
                        let active = player.activeLyrics.last(where: { $0.time <= player.position })
                        Text(active?.text ?? player.activeLyrics.first?.text ?? "")
                            .font(.title3.weight(.semibold)).multilineTextAlignment(.center).lineLimit(2)
                            .foregroundStyle(.white.opacity(0.88)).frame(maxWidth: .infinity).padding(.horizontal, 24).padding(.top, 15)
                    } else if let playbackError = player.playbackError {
                        Text(playbackError).font(.footnote).multilineTextAlignment(.center).foregroundStyle(.orange).padding(.horizontal, 24).padding(.top, 12)
                    }

                    VStack(spacing: 7) {
                        Slider(value: Binding(
                            get: { isScrubbing ? scrubValue : player.position },
                            set: { scrubValue = $0 }
                        ), in: 0...max(player.duration, 1), onEditingChanged: { editing in
                            isScrubbing = editing
                            if !editing { player.seek(to: scrubValue) }
                        })
                        HStack {
                            Text(timeString(isScrubbing ? scrubValue : player.position))
                            Spacer()
                            Text("-\(timeString(max(player.duration - (isScrubbing ? scrubValue : player.position), 0)))")
                        }
                        .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.66))
                    }
                    .padding(.horizontal, 24).padding(.top, 21)

                    HStack(spacing: 0) {
                        Button { player.skip(-1) } label: { Image(systemName: "backward.end.fill").font(.system(size: 30)) }
                        Spacer()
                        Button { player.togglePlayback() } label: {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 37, weight: .bold))
                                .frame(width: 82, height: 82)
                                .background(.white, in: Circle()).foregroundStyle(.black)
                        }
                        Spacer()
                        Button { player.skip(1) } label: { Image(systemName: "forward.end.fill").font(.system(size: 30)) }
                    }
                    .buttonStyle(.plain).padding(.horizontal, 48).padding(.top, 23)

                    Spacer(minLength: 20)
                    HStack {
                        Image(systemName: "hifispeaker.fill").foregroundStyle(.white.opacity(0.75))
                        Spacer()
                        Text("This iPhone").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.76))
                        Spacer()
                        Button { showQueue = true } label: { Image(systemName: "list.bullet").foregroundStyle(.white.opacity(0.75)) }
                    }
                    .padding(.horizontal, 30).padding(.bottom, 25)
                }
            }
            .foregroundStyle(.white)
            .ignoresSafeArea(edges: .bottom)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showQueue) { PlaybackQueueSheet().environmentObject(player) }
    }
}

private struct AnimatedCoverArtwork: View {
    let track: AudioTrack?
    let isPlaying: Bool
    @State private var drifting = false

    var body: some View {
        TrackArtwork(track: track)
            .scaleEffect(drifting ? 1.035 : 0.985)
            .rotation3DEffect(.degrees(drifting ? 1.8 : -1.8), axis: (x: 0, y: 1, z: 0), perspective: 0.7)
            .overlay(LinearGradient(colors: [.white.opacity(drifting ? 0.08 : 0.01), .clear, .black.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .onAppear {
                if isPlaying { withAnimation(.easeInOut(duration: 5.5).repeatForever(autoreverses: true)) { drifting = true } }
            }
            .onChange(of: isPlaying) { _, playing in
                withAnimation(playing ? .easeInOut(duration: 5.5).repeatForever(autoreverses: true) : .spring(response: 0.4)) {
                    drifting = playing
                }
            }
            .accessibilityLabel("Animated album artwork")
    }
}

private struct PlaybackQueueSheet: View {
    @EnvironmentObject private var player: LocalPlayer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(player.queue) { track in
                    Button {
                        player.playQueue(player.queue, startingWith: track)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            TrackArtwork(track: track).frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 7))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(track.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if player.currentTrack?.videoID == track.videoID && track.videoID != nil || player.currentTrack?.id == track.id {
                                Image(systemName: "waveform").foregroundStyle(.tint)
                            }
                            Text("\((player.queue.firstIndex(of: track) ?? 0) + 1)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                        }
                    }.buttonStyle(.plain)
                }
            }
            .navigationTitle("Up Next · \(player.queue.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct CoverFlowArtwork: View {
    @EnvironmentObject private var player: LocalPlayer

    var body: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width * 0.82, proxy.size.height * 0.96)
            let collection = player.queue.isEmpty ? player.tracks : player.queue
            let selected = collection.firstIndex(where: { item in
                if let currentVideo = player.currentTrack?.videoID { return item.videoID == currentVideo }
                return item.id == player.currentTrack?.id
            }) ?? (player.currentIndex ?? 0)
            ZStack {
                if !collection.isEmpty {
                    ForEach(collection.indices, id: \.self) { index in
                        let position = relativePosition(index, current: selected, count: collection.count)
                        if abs(position) <= 3 {
                            let track = collection[index]
                            TrackArtwork(track: track)
                                .frame(width: width, height: width)
                                .clipShape(RoundedRectangle(cornerRadius: 13))
                                .rotation3DEffect(
                                    .degrees(position == 0 ? 0 : (position < 0 ? 38 + Double(abs(position)) * 6 : -38 - Double(abs(position)) * 6)),
                                    axis: (x: 0, y: 1, z: 0),
                                    perspective: 0.58
                                )
                                .scaleEffect(1 - CGFloat(abs(position)) * 0.055)
                                .offset(x: CGFloat(position) * proxy.size.width * 0.13)
                                .shadow(color: .black.opacity(position == 0 ? 0.35 : 0.16), radius: position == 0 ? 17 : 7, y: 10)
                                .zIndex(Double(10 - abs(position)))
                                .animation(.smooth(duration: 0.42), value: selected)
                        }
                    }
                } else {
                    TrackArtwork(track: nil).frame(width: width, height: width).clipShape(RoundedRectangle(cornerRadius: 15))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
    }

    private func relativePosition(_ index: Int, current: Int, count: Int) -> Int {
        var distance = index - current
        if distance > count / 2 { distance -= count }
        if distance < -count / 2 { distance += count }
        return distance
    }
}

private struct VinylArtwork: View {
    let track: AudioTrack?
    let isPlaying: Bool
    @State private var spin = false

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle().fill(Color(red: 0.035, green: 0.04, blue: 0.055))
                ForEach(0..<12, id: \.self) { index in
                    Circle().stroke(.white.opacity(index.isMultiple(of: 2) ? 0.10 : 0.045), lineWidth: 1)
                        .padding(CGFloat(index) * side * 0.026 + side * 0.04)
                }
                TrackArtwork(track: track)
                    .frame(width: side * 0.39, height: side * 0.39)
                    .clipShape(Circle())
                Circle().fill(.white).frame(width: 8, height: 8)
            }
            .frame(width: side, height: side)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .animation(isPlaying ? .linear(duration: 9).repeatForever(autoreverses: false) : .easeOut(duration: 0.2), value: spin)
            .onAppear { spin = isPlaying }
            .onChange(of: isPlaying) { _, newValue in spin = newValue }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct PlayerBackdrop: View {
    let image: UIImage?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(red: 0.08, green: 0.07, blue: 0.13)
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height).clipped()
                        .blur(radius: 42).overlay(Color.black.opacity(0.35))
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height * 0.42)
                        .scaleEffect(x: 1, y: -1).clipped().blur(radius: 20).opacity(0.24)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .overlay(alignment: .bottom) {
                            LinearGradient(colors: [.clear, .black.opacity(0.82)], startPoint: .top, endPoint: .bottom)
                                .frame(height: proxy.size.height * 0.4)
                        }
                    LinearGradient(colors: [.black.opacity(0.18), .black.opacity(0.37)], startPoint: .top, endPoint: .bottom)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .ignoresSafeArea()
        }
    }
}

private struct TrackArtwork: View {
    let track: AudioTrack?

    var body: some View {
        Group {
            if let data = track?.artworkData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else if let url = track?.artworkURL {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { fallback }
            } else {
                fallback
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.23, green: 0.13, blue: 0.38), Color(red: 0.07, green: 0.14, blue: 0.32)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "music.note").font(.system(size: 40, weight: .light)).foregroundStyle(.white.opacity(0.82))
        }
    }
}

private struct TrackRow: View {
    let track: AudioTrack
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                TrackArtwork(track: track).frame(width: 54, height: 54).clipShape(RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title).font(.body.weight(.semibold)).lineLimit(1)
                    Text(track.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 6)
                Image(systemName: "ellipsis").foregroundStyle(.secondary).padding(8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SectionHeading: View {
    let title: String
    let action: String
    let onAction: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title2.bold())
            Spacer()
            Button(action, action: onAction).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
        }
    }
}

private struct MiniPlayer: View {
    @EnvironmentObject private var player: LocalPlayer
    let openPlayer: () -> Void

    var body: some View {
        if let track = player.currentTrack {
            HStack(spacing: 11) {
                Button(action: openPlayer) {
                    HStack(spacing: 10) {
                        TrackArtwork(track: track).frame(width: 42, height: 42).clipShape(RoundedRectangle(cornerRadius: 7))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(track.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)
                Spacer(minLength: 5)
                Button { player.skip(-1) } label: { Image(systemName: "backward.end.fill").font(.system(size: 16)) }
                Button { player.togglePlayback() } label: { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 19, weight: .bold)).frame(width: 34, height: 38) }
                Button { player.skip(1) } label: { Image(systemName: "forward.end.fill").font(.system(size: 16)) }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background {
                if #available(iOS 26.0, *) {
                    RoundedRectangle(cornerRadius: 16).fill(.clear).glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
                } else {
                    RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.08), lineWidth: 1))
                }
            }
            .overlay(alignment: .bottomLeading) {
                GeometryReader { geo in
                    Capsule().fill(.white.opacity(0.8)).frame(width: geo.size.width * (player.duration > 0 ? player.position / player.duration : 0), height: 2)
                }
                .frame(height: 2).padding(.horizontal, 12)
            }
        }
    }
}

private struct MainDock: View {
    @Binding var selected: MainTab
    let onSelect: (MainTab) -> Void
    @Namespace private var dockSelection

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases, id: \.rawValue) { item in
                Button {
                    onSelect(item)
                } label: {
                    Image(systemName: item.symbol)
                        .font(.system(size: 20, weight: selected == item ? .semibold : .regular))
                        .symbolEffect(.bounce, value: selected == item)
                        .foregroundStyle(selected == item ? Color.white : Color.white.opacity(0.58))
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background {
                            if selected == item {
                                if #available(iOS 26.0, *) {
                                    Capsule().fill(Color.white.opacity(0.12))
                                        .glassEffect(.regular, in: Capsule())
                                        .matchedGeometryEffect(id: "dock-selection", in: dockSelection)
                                } else {
                                    Capsule().fill(Color.white.opacity(0.14))
                                        .matchedGeometryEffect(id: "dock-selection", in: dockSelection)
                                }
                            }
                        }
                        .scaleEffect(selected == item ? 1.04 : 1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(selected == item ? .isSelected : [])
                .animation(.spring(response: 0.32, dampingFraction: 0.68), value: selected)
            }
        }
        .padding(5)
        .background {
            if #available(iOS 26.0, *) {
                Capsule().fill(.clear).glassEffect(.regular, in: Capsule())
            } else {
                Capsule().fill(.ultraThinMaterial).overlay(Capsule().stroke(.white.opacity(0.09), lineWidth: 1))
            }
        }
    }
}

private func timeString(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "0:00" }
    let whole = max(0, Int(seconds))
    return "\(whole / 60):\(String(format: "%02d", whole % 60))"
}
