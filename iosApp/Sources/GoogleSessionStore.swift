import Foundation
import Security
import WebKit

enum GoogleSessionStore {
    private static let service = "com.mumixic.ios.google-session"
    private static let account = "youtube-music-cookie"

    static var cookie: String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static var isSignedIn: Bool { cookie.map(hasSigningCookie) ?? false }

    static func save(_ value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(insert as CFDictionary, nil)
    }

    static func clear() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrService as String: service,
                       kSecAttrAccount as String: account] as CFDictionary)
        let store = WKWebsiteDataStore.default().httpCookieStore
        store.getAllCookies { cookies in
            cookies.filter { $0.domain.contains("google.com") || $0.domain.contains("youtube.com") }
                .forEach { store.delete($0) }
        }
    }

    static func hasSigningCookie(_ header: String) -> Bool {
        let names: Set<String> = ["SAPISID", "__Secure-3PAPISID", "__Secure-1PAPISID"]
        return header.split(separator: ";").contains { part in
            let fields = part.split(separator: "=", maxSplits: 1)
            return fields.count == 2 && names.contains(fields[0].trimmingCharacters(in: .whitespaces)) && !fields[1].trimmingCharacters(in: .whitespaces).isEmpty
        }
    }
}
