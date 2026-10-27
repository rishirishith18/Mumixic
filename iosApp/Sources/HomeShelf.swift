import Foundation

struct HomeShelf: Identifiable {
    let id = UUID()
    let title: String
    let items: [AudioTrack]
}
