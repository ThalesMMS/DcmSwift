//  JPEGLSGolombAndContextTests.swift
//  DcmSwift
//
//  Created by Thales on 2025/09/08.
//

import XCTest
@testable import DcmSwift

final class JPEGLSGolombAndContextTests: XCTestCase {
    private func data(fromBits bits: String) -> Data {
        var out: [UInt8] = []
        var acc: UInt8 = 0
        var n: Int = 0
        for ch in bits {
            acc <<= 1
            acc |= (ch == "1") ? 1 : 0
            n += 1
            if n == 8 {
                out.append(acc)
                acc = 0
                n = 0
            }
        }
        if n > 0 { out.append(acc << (8 - n)) }
        return Data(out)
    }

    func testRiceDecodeSimple() {
        // q=1 ("01"), remainder (k=2) = 2 ("10"). Bits "0110" => value 1<<2 + 2 = 6
        let d = data(fromBits: "0110")
        let bs = BitStream(d)
        let v = Golomb.decodeRice(bs, k: 2)
        XCTAssertEqual(v, 6)
    }

    func testGolombDecodeSimple() {
        // Unary terminator immediately ("1"), remainder k=1 => 0 ("0"). Bits "10" => value 0
        let d = data(fromBits: "10")
        let bs = BitStream(d)
        let v = Golomb.decode(bs, k: 1, limit: 512, qbpp: 8)
        XCTAssertEqual(v, 0)
    }

    func testContextMapCount() {
        // Ensure context map spans exactly 365 canonical contexts
        var used = Set<Int>()
        for q1 in -4...4 {
            for q2 in -4...4 {
                for q3 in -4...4 {
                    var a = q1, b = q2, c = q3
                    var s = 1
                    if a < 0 || (a == 0 && b < 0) || (a == 0 && b == 0 && c < 0) { s = -1; a = -a; b = -b; c = -c }
                    let idx = ScanDecoder.contextIndex(q1: max(0,a), q2: max(0,b), q3: max(0,c))
                    used.insert(idx)
                }
            }
        }
        XCTAssertEqual(used.count, 365)
        XCTAssertLessThanOrEqual(used.max() ?? 0, 364)
    }
}

