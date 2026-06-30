#!/usr/bin/env swift
// Signs a release artifact for the in-app updater's fail-closed trust chain (F3).
//
//   SAPAT_SIGNING_KEY=<base64 ed25519 private key> swift scripts/sign-release.swift <file>
//
// Writes two sibling assets next to <file>:
//   <file>.sig     base64 of the 64-byte ed25519 signature over the file's bytes (the trust anchor)
//   <file>.sha256  `shasum`-style checksum (a cheap corruption pre-check for the installer)
//
// The private key lives only in the GitHub Actions secret SAPAT_SIGNING_KEY — never in the repo.
// The matching PUBLIC key is embedded in the app at Sources/ReleaseSignature.swift.
import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("✗ \(message)\n".utf8))
    exit(1)
}

guard CommandLine.arguments.count >= 2 else { fail("usage: sign-release.swift <file>") }
let path = CommandLine.arguments[1]

guard let b64 = ProcessInfo.processInfo.environment["SAPAT_SIGNING_KEY"], !b64.isEmpty,
      let keyData = Data(base64Encoded: b64),
      let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: keyData)
else { fail("SAPAT_SIGNING_KEY is missing or not a valid base64 ed25519 private key") }

guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { fail("cannot read \(path)") }

do {
    let signature = try key.signature(for: data)
    let name = URL(fileURLWithPath: path).lastPathComponent
    try Data(signature.base64EncodedString().utf8).write(to: URL(fileURLWithPath: path + ".sig"))
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    try Data("\(digest)  \(name)\n".utf8).write(to: URL(fileURLWithPath: path + ".sha256"))
    print("✓ Signed \(name) → \(name).sig (ed25519) + \(name).sha256")
} catch {
    fail("signing failed: \(error.localizedDescription)")
}
