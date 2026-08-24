import SwiftUI
import SharedFoundation

// MARK: – EncryptionManager

/// App-layer wrapper around `NoteEncryptionService`.
///
/// Responsibilities:
/// • Publishes `isUnlocked` / `hasPassword` so every view reacts automatically.
/// • Holds sheet-presentation flags so the toolbar can open the right sheet.
/// • Adds UI-level validation (min length, confirmation match) on top of the
///   cryptographic layer.
///
/// Inject as `.environmentObject(EncryptionManager())` from the app entry point.
@MainActor
final class EncryptionManager: ObservableObject {

    // MARK: – Published state

    /// The cryptographic session is open and notes can be decrypted.
    @Published private(set) var isUnlocked: Bool = false

    /// A master password has been configured on this device (salt + canary
    /// exist in Keychain).
    @Published private(set) var hasPassword: Bool = false

    // MARK: – Sheet flags

    @Published var showSetPasswordSheet: Bool = false
    @Published var showUnlockSheet: Bool = false

    // MARK: – Internal

    private let service = NoteEncryptionService.shared

    // MARK: – Init

    init() {
        hasPassword = service.hasPassword
        isUnlocked  = service.isUnlocked
    }

    // MARK: – Password management

    /// Validates and sets a new master password.
    ///
    /// - Parameters:
    ///   - password: The desired password.
    ///   - confirm:  Must equal `password`.
    /// - Throws: `EncryptionUIError` for validation failures,
    ///           `EncryptionError` for cryptographic / Keychain failures.
    func setPassword(_ password: String, confirm: String) throws {
        guard password == confirm else { throw EncryptionUIError.passwordMismatch }
        guard password.count >= 8  else { throw EncryptionUIError.passwordTooShort }
        try service.setPassword(password)
        hasPassword = true
        isUnlocked  = true
    }

    /// Attempts to unlock with `password`.
    /// - Returns: `true` on success, `false` on wrong password.
    @discardableResult
    func unlock(password: String) throws -> Bool {
        let ok = try service.unlock(password: password)
        isUnlocked = ok
        return ok
    }

    /// Clears the in-memory session key without touching Keychain.
    func lock() {
        service.lock()
        isUnlocked = false
    }

    /// Deletes the password, salt, and canary from Keychain.
    func removePassword() {
        service.removePassword()
        hasPassword = false
        isUnlocked  = false
    }

    // MARK: – Convenience pass-throughs

    func encrypt(_ plaintext: String) throws -> String {
        try service.encrypt(plaintext)
    }

    func decrypt(_ encryptedBody: String) throws -> String {
        try service.decrypt(encryptedBody)
    }
}

// MARK: – UI-layer errors

enum EncryptionUIError: LocalizedError {
    case passwordMismatch
    case passwordTooShort

    var errorDescription: String? {
        switch self {
        case .passwordMismatch: return "Passwords do not match."
        case .passwordTooShort: return "Password must be at least 8 characters."
        }
    }
}
