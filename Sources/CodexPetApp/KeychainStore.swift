import Foundation
import CodexPetCore
import Security
import LocalAuthentication

enum KeychainStore {
    private static let service = "CodexDesktopPet"
    private static let openAIAccount = "openai-api-key"
    private static let deepSeekAccount = "deepseek-api-key"

    static func saveOpenAIAPIKey(_ value: String) throws {
        try savePassword(value, account: openAIAccount)
    }

    static func readOpenAIAPIKey() -> String? {
        readPassword(account: openAIAccount)
    }

    static var hasOpenAIAPIKey: Bool {
        hasPassword(account: openAIAccount)
    }

    static func saveExampleAPIKey(_ value: String, provider: ExampleProvider) throws {
        try savePassword(value, account: account(for: provider))
    }

    static func readExampleAPIKey(provider: ExampleProvider) -> String? {
        readPassword(account: account(for: provider))
    }

    static func hasExampleAPIKey(provider: ExampleProvider) -> Bool {
        hasPassword(account: account(for: provider))
    }

    private static func hasPassword(account: String) -> Bool {
        // Saved-status labels must not decrypt credentials or block UI on a Keychain consent dialog.
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    private static func account(for provider: ExampleProvider) -> String {
        switch provider {
        case .openAI: return openAIAccount
        case .deepSeek: return deepSeekAccount
        }
    }

    private static func savePassword(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw keychainError(addStatus)
            }
        } else if status != errSecSuccess {
            throw keychainError(status)
        }
    }

    private static func readPassword(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func keychainError(_ status: OSStatus) -> NSError {
        NSError(
            domain: "CodexDesktopPet.Keychain",
            code: Int(status),
            userInfo: [NSLocalizedDescriptionKey: SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"]
        )
    }
}
