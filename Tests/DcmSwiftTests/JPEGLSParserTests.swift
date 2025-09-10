//  JPEGLSParserTests.swift
//  DcmSwift
//
//  Created by Thales on 2025/09/08.
//

import XCTest
@testable import DcmSwift

final class JPEGLSParserTests: XCTestCase {
    func testParseMinimalSOF55SOS() throws {
        // SOI
        var bytes: [UInt8] = [0xFF, 0xD8]
        // SOF55 (F7): Lf=11, P=8, Y=1, X=1, Nf=1, compspec (3 bytes)
        bytes += [0xFF, 0xF7, 0x00, 0x0B, 0x08, 0x00, 0x01, 0x00, 0x01, 0x01, 0x11, 0x00]
        // SOS: Ls=8, Ns=1, Cs1=1, NEAR=0, ILV=0, mapping=0
        bytes += [0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x00]
        // EOI
        bytes += [0xFF, 0xD9]

        let data = Data(bytes)
        let p = try JPEGLSParser.parse(data)
        XCTAssertEqual(p.width, 1)
        XCTAssertEqual(p.height, 1)
        XCTAssertEqual(p.components, 1)
        XCTAssertEqual(p.bitsPerSample, 8)
        XCTAssertEqual(p.near, 0)
        XCTAssertEqual(p.interleaveMode, 0)
        XCTAssertEqual(p.entropyData.count, 0)
    }
}

