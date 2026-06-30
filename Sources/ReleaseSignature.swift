import CryptoKit
import Foundation

/// Asymmetric verification of release artifacts (F3). The in-app updater installs a downloaded
/// build only after it verifies a detached **ed25519** signature over the exact zip bytes
/// against a public key compiled into the app. The matching private key signs each release in
/// CI and never leaves the GitHub Actions secret store. This is the trust anchor — not the
/// SHA-256, which is fetched from the same untrusted asset channel and only guards corruption.
///
/// Verification is **fail-closed**: a missing, malformed, or non-matching signature aborts the
/// install. We use raw ed25519 via CryptoKit (no third-party dependency; minisign's modern
/// format pre-hashes with BLAKE2b, which CryptoKit can't compute).
enum ReleaseSignature {
    /// Embedded ed25519 PUBLIC key (base64, 32 bytes). Rotating the signing key means shipping
    /// a new app build with a new value here. (Public — safe to commit.)
    static let publicKeyBase64 = "aavnJZp4xBt6McaZIORtKyvFTBTK51ekEDhM2oiPKmE="

    enum SignatureError: LocalizedError, Equatable {
        case missing
        case invalid

        var errorDescription: String? {
            switch self {
            case .missing: return "This update is unsigned and was refused for your safety."
            case .invalid: return "This update failed its signature check and was refused."
            }
        }
    }

    /// Verifies a detached ed25519 signature over `data` against a base64 public key. Pure and
    /// total: any malformed input returns `false` (never throws), so callers fail closed.
    static func verify(data: Data, signature: Data, publicKeyBase64: String) -> Bool {
        guard signature.count == 64,
              let keyData = Data(base64Encoded: publicKeyBase64), keyData.count == 32,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        else { return false }
        return key.isValidSignature(signature, for: data)
    }

    /// Fail-closed gate run before installing an update: throws unless a valid signature is
    /// present. A nil/empty signature is a hard failure (`.missing`); a present-but-wrong one is
    /// `.invalid`.
    static func gate(data: Data, signature: Data?, publicKeyBase64: String = publicKeyBase64) throws {
        guard let signature, !signature.isEmpty else { throw SignatureError.missing }
        guard verify(data: data, signature: signature, publicKeyBase64: publicKeyBase64) else {
            throw SignatureError.invalid
        }
    }

    /// Parses a `.sig` asset body into the 64-byte signature. Accepts base64 (the format CI
    /// writes, tolerating surrounding whitespace) or already-raw 64 bytes.
    static func parseSignature(_ raw: Data) -> Data? {
        let text = String(decoding: raw, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if let decoded = Data(base64Encoded: text), decoded.count == 64 { return decoded }
        if raw.count == 64 { return raw }
        return nil
    }
}
