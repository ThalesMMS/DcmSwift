//  JPEGLSInterleaveAndNearTests.swift
//  DcmSwift
//
//  Created by Thales on 2025/09/08.
//

import XCTest
@testable import DcmSwift

final class JPEGLSInterleaveAndNearTests: XCTestCase {
    func testParserMultipleScansForILVNone() throws {
        // Build a minimal codestream with SOI, SOF55 (2 components), two SOS (one per component), and EOI.
        var bytes: [UInt8] = [0xFF, 0xD8] // SOI
        // SOF55: 2 comps, 8bpp, 2x1
        bytes += [0xFF, 0xF7, 0x00, 0x0E, 0x08, 0x00, 0x01, 0x00, 0x02, 0x02,
                  0x01, 0x11, 0x00,  // comp1 spec
                  0x02, 0x11, 0x00]  // comp2 spec
        // SOS #1: Ns=1, Cs1=1, NEAR=0, ILV=0; no entropy
        bytes += [0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x00]
        // Add immediate marker to terminate entropy (EOI)
        bytes += [0xFF, 0xD9]
        // Start a new SOS for second component (this is a simplification for test parsing)
        bytes += [0xFF, 0xDA, 0x00, 0x08, 0x01, 0x02, 0x00, 0x00, 0x00]
        bytes += [0xFF, 0xD9]

        let data = Data(bytes)
        let p = try JPEGLSParser.parse(data)
        XCTAssertEqual(p.components, 2)
        XCTAssertEqual(p.scanEntropies.count, 2)
        XCTAssertEqual(p.scanComponents.count, 2)
        XCTAssertEqual(p.interleaveMode, 0)
    }

    func testThresholdsIncreaseWithNear() {
        let t0 = JLSState.defaultThresholds(8, near: 0)
        let t3 = JLSState.defaultThresholds(8, near: 3)
        XCTAssertLessThan(t0.T1, t3.T1)
        XCTAssertLessThan(t0.T2, t3.T2)
        XCTAssertLessThan(t0.T3, t3.T3)
    }
}

