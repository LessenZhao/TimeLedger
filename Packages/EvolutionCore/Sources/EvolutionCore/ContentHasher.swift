import CryptoKit
import Foundation

public enum ContentHasher {
    public static func hash(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func hashParts(_ parts: [String]) -> String {
        hash(parts.joined(separator: "\u{1e}"))
    }
}
