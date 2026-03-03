//
//  AESDecryptHelper.m
//  ClashX
//

#import "AESDecryptHelper.h"
#import <CommonCrypto/CommonCrypto.h>

NSData * _Nullable AES128CBCDecrypt(NSData *key, NSData *iv, NSData *cipher) {
    if (key.length != 16 || iv.length != 16 || cipher.length == 0) return nil;
    size_t outLength = 0;
    size_t outCapacity = cipher.length + kCCBlockSizeAES128;
    void *outBytes = malloc(outCapacity);
    if (!outBytes) return nil;
    CCCryptorStatus status = CCCrypt(
        kCCDecrypt,
        kCCAlgorithmAES,
        kCCOptionPKCS7Padding,
        key.bytes, key.length,
        iv.bytes,
        cipher.bytes, cipher.length,
        outBytes, outCapacity,
        &outLength
    );
    if (status != kCCSuccess) {
        free(outBytes);
        return nil;
    }
    NSData *result = [NSData dataWithBytes:outBytes length:outLength];
    free(outBytes);
    return result;
}
