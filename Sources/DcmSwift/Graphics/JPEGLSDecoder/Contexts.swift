//
//  Contexts.swift
//  DcmSwift
//
//  Created by Thales on 2025/09/10.
// 
//  JPEG-LS context state and default thresholds.
//

import Foundation

struct JLSState {
    // Regular mode contexts (365)
    var A: [Int]
    var B: [Int]
    var C: [Int]
    var N: [Int]
    // Run mode counters
    var RUNindex: Int = 0
    var RUNindexPrev: Int = 0
    // Thresholds
    let T1: Int
    let T2: Int
    let T3: Int
    let RESET: Int

    init(bitsPerSample: Int) {
        let size = 365
        self.A = [Int](repeating: 4, count: size)
        self.B = [Int](repeating: 0, count: size)
        self.C = [Int](repeating: 0, count: size)
        self.N = [Int](repeating: 1, count: size)
        let t = JLSState.defaultThresholds(bitsPerSample)
        self.T1 = t.T1; self.T2 = t.T2; self.T3 = t.T3; self.RESET = t.RESET
    }

    static func defaultThresholds(_ bpp: Int, near: Int = 0) -> (T1: Int, T2: Int, T3: Int, RESET: Int) {
        // Default thresholds per Annex: for near=0
        let maxval = (1 << bpp) - 1
        var T1 = 3
        var T2 = 7
        var T3 = 21
        if bpp >= 8 {
            T1 = 3 + ((maxval + 32) >> 6)
            T2 = 7 + ((maxval + 32) >> 6)
            T3 = 21 + ((maxval + 32) >> 6)
        } else {
            T1 = 3
            T2 = 7
            T3 = 21
        }
        return (T1, T2, T3, 64)
    }
}

