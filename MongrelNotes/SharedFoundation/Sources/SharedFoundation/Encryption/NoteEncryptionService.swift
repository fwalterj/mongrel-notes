import CryptoKit
import Foundation
import Security

// MARK: – NoteEncryptionService

/// Handles all cryptographic operations for per-note local encryption.
///
/// **Model**
/// One master password unlocks all encrypted notes for the session.
/// The key is derived once from the password and held in memory;
/// it is never written to disk in plaintext.
///
/// **Key derivation**
/// `PBKDF2-HMAC-SHA256` with a random 16-byte salt stored in the macOS
/// Keychain.  100 000 iterations (NIST 800-132 minimum for interactive use).
///
/// **Cipher**
/// `AES-GCM` (256-bit) via Apple's `CryptoKit`.  A fresh 12-byte nonce is
/// generated for every encrypt call.  The authentication tag is included in
/// the ciphertext so tampering is detected on decrypt.
///
/// **On-disk format** (stored as the `body` field of a `.md` file)
/// ```
/// ---mongrel-encrypted-v1---
/// <base64-nonce>:<base64-ciphertext+tag>
/// ```
///
/// **Keychain items**
/// • `com.mongrel.notes.enc.salt`   — 16-byte random salt (not secret)
/// • `com.mongrel.notes.enc.canary` — nonce:ciphertext of a known string,
///   used to verify the password is correct without decrypting real notes.
public final class NoteEncryptionService {

    // MARK: – Singleton

    public static let shared = NoteEncryptionService()

    // MARK: – Constants

    public static let encryptedHeader = "---mongrel-encrypted-v1---\n"
    private static let saltKeychainKey   = "com.mongrel.notes.enc.salt"
    private static let canaryKeychainKey = "com.mongrel.notes.enc.canary"
    private static let canaryPlaintext   = "mongrel-notes-canary-v1"
    private static let pbkdf2Iterations  = 100_000

    // MARK: – State

    /// The in-memory session key.  Cleared on `lock()`.
    private var sessionKey: SymmetricKey?

    /// Whether a password has ever been configured for this device.
    public var hasPassword: Bool {
        loadFromKeychain(key: Self.canaryKeychainKey) != nil
    }

    /// Whether the app is currently unlocked (session key in memory).
    public var isUnlocked: Bool { sessionKey != nil }

    // MARK: – Init (private — use `shared`)

    private init() {}

    // MARK: – Public API

    /// Sets a new master password.  Derives the key, stores the salt and
    /// a verification canary in Keychain, then arms the session.
    /// - Throws: `EncryptionError.keychainFailure` if Keychain writes fail.
    public func setPassword(_ password: String) throws {
        // Generate a fresh random salt.
        var saltBytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, saltBytes.count, &saltBytes) == errSecSuccess
        else { throw EncryptionError.randomGenerationFailed }

        let salt = Data(saltBytes)
        let key  = try deriveKey(from: password, salt: salt)

        // Store the salt in Keychain (not secret, but persisted).
        try saveToKeychain(key: Self.saltKeychainKey, data: salt)

        // Encrypt a known canary so we can verify the password later.
        let canaryData = Data(Self.canaryPlaintext.utf8)
        let sealedCanary = try AES.GCM.seal(canaryData, using: key)
        guard let canaryEncoded = sealedCanary.combined else {
            throw EncryptionError.sealFailed
        }
        try saveToKeychain(key: Self.canaryKeychainKey, data: canaryEncoded)

        sessionKey = key
    }

    /// Attempts to unlock with the given password.
    /// - Returns: `true` if the password matched, `false` otherwise.
    /// - Throws: `EncryptionError` if Keychain data is missing or corrupt.
    @discardableResult
    public func unlock(password: String) throws -> Bool {
        guard let saltData   = loadFromKeychain(key: Self.saltKeychainKey),
              let canaryData = loadFromKeychain(key: Self.canaryKeychainKey)
        else { throw EncryptionError.noPasswordConfigured }

        let key = try deriveKey(from: password, salt: saltData)

        // Verify against the canary.
        let sealedCanary = try AES.GCM.SealedBox(combined: canaryData)
        guard let decrypted = try? AES.GCM.open(sealedCanary, using: key),
              String(data: decrypted, encoding: .utf8) == Self.canaryPlaintext
        else {
            return false  // wrong password — do not arm the session
        }

        sessionKey = key
        return true
    }

    /// Clears the session key from memory.  Encrypted notes can no longer be read.
    public func lock() {
        sessionKey = nil
    }

    /// Removes the password, salt, and canary from Keychain.
    /// After this call `hasPassword` returns `false`.
    public func removePassword() {
        deleteFromKeychain(key: Self.saltKeychainKey)
        deleteFromKeychain(key: Self.canaryKeychainKey)
        sessionKey = nil
    }

    // MARK: – Encrypt / decrypt note body

    /// Encrypts a plaintext note body and returns the on-disk encrypted form.
    /// - Throws: `EncryptionError.locked` if no session key is present.
    public func encrypt(_ plaintext: String) throws -> String {
        guard let key = sessionKey else { throw EncryptionError.locked }
        let data   = Data(plaintext.utf8)
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else { throw EncryptionError.sealFailed }
        return Self.encryptedHeader + combined.base64EncodedString()
    }

    /// Decrypts an encrypted note body and returns the plaintext.
    /// - Throws: `EncryptionError.locked` if not unlocked,
    ///           `EncryptionError.decryptionFailed` if the ciphertext is corrupt.
    public func decrypt(_ encryptedBody: String) throws -> String {
        guard let key = sessionKey else { throw EncryptionError.locked }
        guard encryptedBody.hasPrefix(Self.encryptedHeader) else {
            return encryptedBody   // not encrypted — pass through
        }

        let b64 = String(encryptedBody.dropFirst(Self.encryptedHeader.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let combined = Data(base64Encoded: b64) else {
            throw EncryptionError.decryptionFailed
        }

        let sealed    = try AES.GCM.SealedBox(combined: combined)
        let plainData = try AES.GCM.open(sealed, using: key)
        guard let text = String(data: plainData, encoding: .utf8) else {
            throw EncryptionError.decryptionFailed
        }
        return text
    }

    // MARK: – Key derivation (PBKDF2-SHA256)

    private func deriveKey(from password: String, salt: Data) throws -> SymmetricKey {
        guard let passwordData = password.data(using: .utf8) else {
            throw EncryptionError.invalidPassword
        }

        var derivedKey = [UInt8](repeating: 0, count: 32)  // 256-bit
        let status = passwordData.withUnsafeBytes { pwBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    pwBytes.baseAddress, passwordData.count,
                    saltBytes.baseAddress, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(Self.pbkdf2Iterations),
                    &derivedKey, derivedKey.count
                )
            }
        }
        guard status == kCCSuccess else { throw EncryptionError.keyDerivationFailed }
        return SymmetricKey(data: Data(derivedKey))
    }

    // MARK: – Keychain helpers

    private func saveToKeychain(key: String, data: Data) throws {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrAccount: key as CFString,
            kSecValueData:   data,
            // Accessible after first unlock, not backed up to iCloud.
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemDelete(query as CFDictionary)   // remove any previous value
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw EncryptionError.keychainFailure(status) }
    }

    private func loadFromKeychain(key: String) -> Data? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrAccount:      key as CFString,
            kSecReturnData:       kCFBooleanTrue!,
            kSecMatchLimit:       kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return data
    }

    private func deleteFromKeychain(key: String) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrAccount: key as CFString,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: – CCKeyDerivationPBKDF bridge

// CommonCrypto is available on Apple platforms but not directly importable in SPM.
// We declare the symbols we need as @_silgen_name C functions.

private let kCCPBKDF2:          Int32 = 2
private let kCCPRFHmacAlgSHA256: Int32 = 4
private let kCCSuccess:         Int32 = 0

@_silgen_name("CCKeyDerivationPBKDF")
private func CCKeyDerivationPBKDF(
    _ algorithm: CCPBKDFAlgorithm,
    _ password: UnsafeRawPointer?, _ passwordLen: Int,
    _ salt: UnsafeRawPointer?,     _ saltLen: Int,
    _ prf: CCPseudoRandomAlgorithm,
    _ rounds: UInt32,
    _ derivedKey: UnsafeMutableRawPointer?, _ derivedKeyLen: Int
) -> Int32

private typealias CCPBKDFAlgorithm      = UInt32
private typealias CCPseudoRandomAlgorithm = UInt32

// MARK: – Errors

public enum EncryptionError: Error, LocalizedError {
    case locked
    case noPasswordConfigured
    case invalidPassword
    case keyDerivationFailed
    case randomGenerationFailed
    case sealFailed
    case decryptionFailed
    case keychainFailure(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .locked:                return "Notes are locked. Enter your password to unlock."
        case .noPasswordConfigured:  return "No encryption password has been set."
        case .invalidPassword:       return "The password could not be encoded."
        case .keyDerivationFailed:   return "Key derivation failed."
        case .randomGenerationFailed:return "Could not generate random bytes."
        case .sealFailed:            return "Encryption seal failed."
        case .decryptionFailed:      return "Decryption failed — wrong password or corrupt data."
        case .keychainFailure(let s):return "Keychain error (OSStatus \(s))."
        }
    }
}
