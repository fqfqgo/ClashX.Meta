//
//  SubscriptionDecrypt.swift
//  ClashX
//
//  Subscription decryption (AES-128-CBC), compatible with sspanel / v2rayN / FlClash.
//

import Foundation

/// HTTP response header for subscription encryption (same as v2rayN / FlClash)
let kSubscriptionEncryptionHeader = "Subscription-Encryption"
let kSubscriptionEncryptionValue = "true"

/// Check if response headers indicate AES-encrypted subscription
func isSubscriptionEncrypted(headerValue: String?) -> Bool {
    guard let v = headerValue?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return false }
    return v.lowercased() == kSubscriptionEncryptionValue
}

/// MD5 hash of string, returns 32-char hex
private func md5Hex(_ input: String) -> String? {
    guard let data = input.data(using: .utf8) else { return nil }
    var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
    data.withUnsafeBytes { buf in
        _ = CC_MD5(buf.baseAddress, CC_LONG(data.count), &digest)
    }
    return digest.map { String(format: "%02hhx", $0) }.joined()
}

/// First 16 bytes from 32-char hex string
private func hexTo16Bytes(_ hex: String) -> Data? {
    guard hex.count == 32 else { return nil }
    var data = Data(capacity: 16)
    var i = hex.startIndex
    for _ in 0..<16 {
        guard hex.distance(from: i, to: hex.endIndex) >= 2,
              let byte = UInt8(hex[i...hex.index(after: i)], radix: 16) else { return nil }
        data.append(byte)
        i = hex.index(i, offsetBy: 2)
    }
    return data
}

/// Try to decrypt subscription content (AES-128-CBC, same as v2rayN / FlClash).
/// Key: first 16 bytes of MD5(password) hex; IV: first 16 bytes of base64 decoded; Cipher: bytes 16..
func tryDecryptSubscription(password: String, base64Data: Data) -> Data? {
    guard !password.isEmpty, !base64Data.isEmpty else { return nil }
    guard let base64Str = String(data: base64Data, encoding: .utf8) else { return nil }
    let normalized = base64Str.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\r", with: "")
    guard let raw = Data(base64Encoded: normalized), raw.count > 16 else { return nil }
    guard let passHash = md5Hex(password), let keyData = hexTo16Bytes(passHash) else { return nil }
    let iv = raw.subdata(in: 0..<16)
    let cipher = raw.subdata(in: 16..<raw.count)
    return aesDecrypt(key: keyData, iv: iv, cipher: cipher)
}

private func aesDecrypt(key: Data, iv: Data, cipher: Data) -> Data? {
    var outLength: size_t = 0
    let outCapacity = cipher.count + kCCBlockSizeAES128
    var outBytes = [UInt8](repeating: 0, count: outCapacity)
    let status = key.withUnsafeBytes { kBuf in
        iv.withUnsafeBytes { iBuf in
            cipher.withUnsafeBytes { cBuf in
                CCCrypt(
                    CCOperation(kCCDecrypt),
                    CCAlgorithm(kCCAlgorithmAES),
                    CCOptions(kCCOptionPKCS7Padding),
                    kBuf.baseAddress, key.count,
                    iBuf.baseAddress,
                    cBuf.baseAddress, cipher.count,
                    &outBytes, outCapacity,
                    &outLength
                )
            }
        }
    }
    guard status == kCCSuccess else { return nil }
    return Data(bytes: outBytes, count: outLength)
}
