//
//  File.swift
//  
//
//  Created by Colombe on 09/07/2021.
//

import Foundation
import DcmSwift
import XCTest


class DcmSwiftTestsUID: XCTestCase {
    // UID
    public func testValidateUID() {
        let valUID = "1.102.99"
        XCTAssertTrue(UID.validate(uid: valUID))

        // component "0" should be considered valid
        let valUIDWithZero = "1.2.840.10008.0.1.1"
        XCTAssertTrue(UID.validate(uid: valUIDWithZero))

        let invalUID1 = "1.012.5"
        let invalUID2 = "coucou"

        XCTAssertFalse(UID.validate(uid: invalUID1))
        XCTAssertFalse(UID.validate(uid: invalUID2))
    }
    
    public func testGenerateUID() {
        let valUID = "1.102.99"
        XCTAssertNotNil(UID.generate(root: valUID))
    }

}
