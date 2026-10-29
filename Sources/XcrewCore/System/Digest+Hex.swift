import CryptoKit

extension SHA256.Digest {
    /// The digest as lowercase hex, two digits a byte.
    var hex: String {
        map { byte in (byte < 16 ? "0" : "") + String(byte, radix: 16) }.joined()
    }
}
