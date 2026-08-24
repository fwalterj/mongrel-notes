import SwiftUI
import SharedFoundation

// MARK: – Set Password Sheet

/// Presented the first time the user chooses to encrypt a note (or from Settings).
/// Allows the user to set a master password that will protect all encrypted notes.
struct SetPasswordSheet: View {

    @EnvironmentObject private var enc: EncryptionManager
    @Environment(\.dismiss) private var dismiss

    @State private var password: String = ""
    @State private var confirm:  String = ""
    @State private var errorMessage: String? = nil

    @FocusState private var focusField: Field?
    private enum Field { case password, confirm }

    var body: some View {
        GlassSheetContainer(title: "Set Encryption Password", icon: "lock.fill") {
            VStack(alignment: .leading, spacing: 16) {

                Text("Choose a master password. All notes you encrypt will be locked with this password. The password is never stored on disk — only a secure verification token is kept in your Mac's Keychain.")
                    .font(.callout)
                    .foregroundStyle(DesignTokens.chromeText.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 8) {
                    SecureField("Password (min. 8 characters)", text: $password)
                        .textFieldStyle(.plain)
                        .font(DesignTokens.uiFont)
                        .focused($focusField, equals: .password)
                        .onSubmit { focusField = .confirm }
                        .padding(10)
                        .glassChromeBackground(style: .card, cornerRadius: 8)

                    SecureField("Confirm password", text: $confirm)
                        .textFieldStyle(.plain)
                        .font(DesignTokens.uiFont)
                        .focused($focusField, equals: .confirm)
                        .onSubmit { attemptSet() }
                        .padding(10)
                        .glassChromeBackground(style: .card, cornerRadius: 8)
                }

                if let err = errorMessage {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.85))
                }
            }
            .padding(.bottom, 4)

            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(GlassButtonStyle(isDestructive: false, isProminent: false))
                Button("Set Password") { attemptSet() }
                    .buttonStyle(GlassButtonStyle(isDestructive: false, isProminent: true))
                    .disabled(password.isEmpty || confirm.isEmpty)
            }
        }
        .onAppear { focusField = .password }
    }

    private func attemptSet() {
        do {
            try enc.setPassword(password, confirm: confirm)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: – Unlock Sheet

/// Presented when the user tries to open an encrypted note while the session is locked.
struct UnlockSheet: View {

    @EnvironmentObject private var enc: EncryptionManager
    @Environment(\.dismiss) private var dismiss

    /// Called immediately after a successful unlock so the editor can decrypt.
    var onUnlocked: (() -> Void)?

    @State private var password: String     = ""
    @State private var errorMessage: String? = nil
    @State private var shaking: Bool         = false

    @FocusState private var focused: Bool

    init(onUnlocked: (() -> Void)? = nil) { self.onUnlocked = onUnlocked }

    var body: some View {
        GlassSheetContainer(title: "Unlock Notes", icon: "lock.open.fill") {
            VStack(alignment: .leading, spacing: 14) {

                Text("Enter your master password to decrypt and view encrypted notes.")
                    .font(.callout)
                    .foregroundStyle(DesignTokens.chromeText.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)

                SecureField("Master password", text: $password)
                    .textFieldStyle(.plain)
                    .font(DesignTokens.uiFont)
                    .focused($focused)
                    .onSubmit { attemptUnlock() }
                    .padding(10)
                    .glassChromeBackground(style: .card, cornerRadius: 8)
                    // Shake on wrong password
                    .offset(x: shaking ? -6 : 0)
                    .animation(
                        shaking
                            ? .spring(response: 0.08, dampingFraction: 0.2)
                                .repeatCount(4, autoreverses: true)
                            : .default,
                        value: shaking
                    )

                if let err = errorMessage {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.85))
                }
            }
            .padding(.bottom, 4)

            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(GlassButtonStyle(isDestructive: false, isProminent: false))
                Button("Unlock") { attemptUnlock() }
                    .buttonStyle(GlassButtonStyle(isDestructive: false, isProminent: true))
                    .disabled(password.isEmpty)
            }
        }
        .onAppear { focused = true }
    }

    private func attemptUnlock() {
        do {
            let ok = try enc.unlock(password: password)
            if ok {
                onUnlocked?()
                dismiss()
            } else {
                errorMessage = "Incorrect password."
                password     = ""
                shaking      = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { shaking = false }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: – Locked Note Overlay

/// Full-coverage overlay shown in the editor when the selected note is encrypted
/// but the session is currently locked.
struct LockedNoteOverlay: View {

    @EnvironmentObject private var enc: EncryptionManager
    let onUnlocked: () -> Void

    @State private var showUnlockSheet: Bool = false

    var body: some View {
        ZStack {
            // Frosted blur over the editor area
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 22) {

                // ── Icon badge ────────────────────────────────────────────
                ZStack {
                    Circle()
                        .fill(DesignTokens.glassDeep)
                        .frame(width: 80, height: 80)
                    Circle()
                        .strokeBorder(DesignTokens.glassBorder, lineWidth: 1)
                        .frame(width: 80, height: 80)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(DesignTokens.accent)
                }
                .shadow(color: DesignTokens.activeCardGlow, radius: 20, x: 0, y: 6)

                // ── Label ─────────────────────────────────────────────────
                VStack(spacing: 6) {
                    Text("This note is encrypted")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(DesignTokens.chromeText)
                    Text(enc.isUnlocked
                        ? "Tap \"Decrypt\" to open this note."
                         : "Enter your password to unlock all encrypted notes.")
                        .font(.callout)
                        .foregroundStyle(DesignTokens.chromeText.opacity(0.55))
                        .multilineTextAlignment(.center)
                }

                // ── Action ────────────────────────────────────────────────
                Button {
                    if enc.isUnlocked {
                        onUnlocked()
                    } else {
                        showUnlockSheet = true
                    }
                } label: {
                    Label(enc.isUnlocked ? "Decrypt Note" : "Unlock…",
                          systemImage: enc.isUnlocked ? "lock.open" : "key")
                }
                .buttonStyle(GlassButtonStyle(isDestructive: false, isProminent: true))
            }
            .padding(48)
        }
        .sheet(isPresented: $showUnlockSheet) {
            UnlockSheet(onUnlocked: onUnlocked)
        }
    }
}

// MARK: – Glass sheet container

/// Shared scaffold for encryption-related sheets.
/// Provides the frosted glass background, title row, and divider.
struct GlassSheetContainer<Content: View>: View {

    let title:   String
    let icon:    String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            // Header row
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(DesignTokens.accent.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(DesignTokens.accent)
                }
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(DesignTokens.chromeText)
            }

            Divider()
                .foregroundStyle(DesignTokens.borderRim)

            content
        }
        .padding(24)
        .frame(width: 380)
        .glassChromeBackground(
            style: .elevated,
            cornerRadius: DesignTokens.cornerRadius,
            glowShadow: true
        )
    }
}

// MARK: – Glass button style

/// Tinted capsule button consistent with the visionOS glass aesthetic.
/// Used in encryption sheets, but also available as a shared component.
struct GlassButtonStyle: ButtonStyle {

    let isDestructive: Bool
    let isProminent:   Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.callout, weight: isProminent ? .semibold : .regular))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(background(pressed: configuration.isPressed))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(
                .spring(response: 0.18, dampingFraction: 0.7),
                value: configuration.isPressed
            )
    }

    private var foregroundColor: Color {
        if isDestructive { return .red.opacity(0.9) }
        return isProminent
            ? DesignTokens.accent
            : DesignTokens.chromeText.opacity(0.75)
    }

    private func background(pressed: Bool) -> some View {
        let fill: Color = isProminent
            ? DesignTokens.accent.opacity(pressed ? 0.22 : 0.14)
            : DesignTokens.glassCard.opacity(pressed ? 0.60 : 0.40)
        let border: Color = isProminent
            ? DesignTokens.accent.opacity(0.45)
            : DesignTokens.borderRim

        return RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(border, lineWidth: 0.5)
            )
    }
}
