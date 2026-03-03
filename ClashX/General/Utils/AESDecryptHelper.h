//
//  AESDecryptHelper.h
//  ClashX
//
//  AES-128-CBC decrypt for subscription (used by SubscriptionDecrypt.swift).
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Decrypts data with AES-128-CBC (PKCS7 padding). Returns nil on failure.
NSData * _Nullable AES128CBCDecrypt(NSData *key, NSData *iv, NSData *cipher);

NS_ASSUME_NONNULL_END
