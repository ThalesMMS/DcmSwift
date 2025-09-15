//
//  Golomb.swift
//  DcmSwift
//
//  Created by Thales on 2025/09/10.
// 
//  Adaptive Golomb decoder skeleton for JPEG-LS.
//

import Foundation

enum Golomb {
    /// Decodes a non-negative integer using Golomb coding with parameter k and limit.
    /// Updates `k` adaptively via context state as per JPEG-LS. This is a placeholder.
    static func decode(_ bs: BitStream, k: Int, limit: Int, qbpp: Int) -> Int? {
        // Regular-mode Golomb code per JPEG-LS: unary prefix (count of 0s) terminated by 1, truncated by `limit`.
        // If count reaches (limit - 1), read `qbpp` bits for escape value.
        var count = 0
        while count < (limit - 1) {
            guard let bit = bs.readBits(1) else { return nil }
            if bit == 1 { break }
            count += 1
        }

        if count < (limit - 1) {
            // Read remainder of length k
            let remBits = k
            let rem: Int
            if remBits == 0 {
                rem = 0
            } else {
                guard let r = bs.readBits(remBits) else { return nil }
                rem = Int(r)
            }
            return (count << k) + rem
        } else {
            // Escape: read qbpp bits
            guard let v = bs.readBits(qbpp) else { return nil }
            return Int(v)
        }
    }

    /// Decode standard Rice/Golomb code used by run/interruption with fixed parameter k (no limit handling here).
    static func decodeRice(_ bs: BitStream, k: Int) -> Int? {
        var q = 0
        while true {
            guard let bit = bs.readBits(1) else { return nil }
            if bit == 1 { break }
            q += 1
        }
        let r: Int
        if k == 0 { r = 0 } else { guard let rb = bs.readBits(k) else { return nil }; r = Int(rb) }
        return (q << k) + r
    }
}
