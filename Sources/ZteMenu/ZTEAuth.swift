import Foundation
import CryptoKit

enum ZTEAuth {
    static func loginHash(password: String, ld: String) -> String {
        let inner = sha256Hex(password).uppercased()
        return sha256Hex(inner + ld).uppercased()
    }

    private static func sha256Hex(_ s: String) -> String {
        let digest = SHA256.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
