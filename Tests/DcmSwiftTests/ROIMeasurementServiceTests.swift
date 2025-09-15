//  ROIMeasurementServiceTests.swift
//  DcmSwift
//
//  Created by Thales on 2025/09/08.
//

import XCTest
import CoreGraphics
@testable import DcmSwift

final class ROIMeasurementServiceTests: XCTestCase {
    func testDistanceMeasurement() {
        let service = ROIMeasurementService()
        service.updatePixelSpacing(PixelSpacing(x: 0.5, y: 0.5))
        service.startDistanceMeasurement(at: CGPoint(x: 0, y: 0))
        service.addMeasurementPoint(CGPoint(x: 3, y: 4))
        let result = service.completeMeasurement()
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.rawValue, 2.5, accuracy: 0.001)
    }
}
