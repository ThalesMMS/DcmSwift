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
    // Regular mode contexts (365 canonical contexts)
    var A: [Int]
    var B: [Int]
    var C: [Int]
    var N: [Int]
    // Run mode counters
    var RUNindex: Int = 0
    var RUNindexPrev: Int = 0
    // Run-interruption (RI) contexts: type 0 (Ra != Rb), type 1 (Ra == Rb)
    var A_RI: [Int] // size 2
    var N_RI: [Int] // size 2
    var Nn: [Int]   // size 2, count of negative errors
    // Thresholds
    let T1: Int
    let T2: Int
    let T3: Int
    let RESET: Int

    init(bitsPerSample: Int, near: Int = 0) {
        let size = 365
        self.A = [Int](repeating: 4, count: size)
        self.B = [Int](repeating: 0, count: size)
        self.C = [Int](repeating: 0, count: size)
        self.N = [Int](repeating: 1, count: size)
        self.A_RI = [4, 4]
        self.N_RI = [1, 1]
        self.Nn = [0, 0]
        let t = JLSState.defaultThresholds(bitsPerSample, near: near)
        self.T1 = t.T1; self.T2 = t.T2; self.T3 = t.T3; self.RESET = t.RESET
    }

    static func defaultThresholds(_ bpp: Int, near: Int = 0) -> (T1: Int, T2: Int, T3: Int, RESET: Int) {
        // Default thresholds (heuristic for near>0)
        let maxval = (1 << bpp) - 1
        let base1: Int
        let base2: Int
        let base3: Int
        if bpp >= 8 {
            base1 = 3 + ((maxval + 32) >> 6)
            base2 = 7 + ((maxval + 32) >> 6)
            base3 = 21 + ((maxval + 32) >> 6)
        } else {
            base1 = 3
            base2 = 7
            base3 = 21
        }
        // Increase thresholds with NEAR (approximate per Annex guidelines)
        let T1 = base1 + 2 * near
        let T2 = base2 + 3 * near
        let T3 = base3 + 4 * near
        let RESET = 64
        return (T1, T2, T3, RESET)
    }
}
