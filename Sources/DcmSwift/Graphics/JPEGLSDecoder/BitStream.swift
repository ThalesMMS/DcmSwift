//
//  BitStream.swift
//  DcmSwift
//
//  Created by Thales on 2025/09/10.
// 
//  Minimal MSB-first bit reader for JPEG-LS scaffolding.
//

import Foundation

final class BitStream {
    private let data: Data
    private var byteIndex: Int = 0
    private var bitBuffer: UInt32 = 0
    private var bitsInBuffer: Int = 0

    init(_ data: Data) { self.data = data }

    private func refillIfNeeded(_ nbits: Int) {
        while bitsInBuffer < nbits && byteIndex < data.count {
            bitBuffer = (bitBuffer << 8) | UInt32(data[byteIndex])
            byteIndex += 1
            bitsInBuffer += 8
        }
    }

    func readBits(_ n: Int) -> UInt32? {
        guard n > 0 && n <= 24 else { return nil }
        refillIfNeeded(n)
        guard bitsInBuffer >= n else { return nil }
        let shift = bitsInBuffer - n
        let mask: UInt32 = (n == 32) ? 0xFFFF_FFFF : ((1 << n) - 1).toUInt32
        let val = (bitBuffer >> shift) & mask
        bitBuffer &= (1 << shift) - 1
        bitsInBuffer -= n
        return val
    }
}

private extension Int {
    var toUInt32: UInt32 { return UInt32(self) }
}

