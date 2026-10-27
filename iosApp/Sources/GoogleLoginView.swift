import SwiftUI
import WebKit

struct GoogleLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    let onSignedIn: () -> Void

    var body: some View {
        NavigationStack {
            GoogleLoginWebView(onCookie: { cookie in
                guard GoogleSessionStore.hasSigningCookie(cookie) else {
                    errorMessage = "Google returned to YouTube Music, but no usable sign-in session was found."
                    return
                }
                GoogleSessionStore.save(cookie)
                onSignedIn()
                dismiss()
            }, onError: { errorMessage = $0 })
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Sign in with Google")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } }
                }
                .alert("Sign-in unavailable", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                    Button("OK", role: .cancel) { errorMessage = nil }
                } message: { Text(errorMessage ?? "") }
        }
    }
}

private struct GoogleLoginWebView: UIViewRepresentable {
    let onCookie: (String) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCookie: onCookie, onError: onError) }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Version/17.0 Mobile/15E148 Safari/604.1"
        webView.load(URLRequest(url: URL(string: "https://accounts.google.com/ServiceLogin?ltmpl=music&service=youtube&prompt=select_account&continue=https%3A%2F%2Fmusic.youtube.com%2F")!))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onCookie: (String) -> Void
        private let onError: (String) -> Void
        private var captured = false

        init(onCookie: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
            self.onCookie = onCookie; self.onError = onError
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !captured, webView.url?.host?.hasSuffix("youtube.com") == true else { return }
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                let selected = cookies.filter { cookie in
                    cookie.domain.contains("google.com") || cookie.domain.contains("youtube.com")
                }
                let header = selected.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                guard GoogleSessionStore.hasSigningCookie(header) else { return }
                self?.captured = true
                DispatchQueue.main.async { self?.onCookie(header) }
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onError("Could not open Google sign-in. Check your connection and try again.")
        }
    }
}
