//  WindowLevelCalculatorTests.swift
//  DcmSwift
//
//  Created by Thales on 2025/09/08.
//

import XCTest
import DcmSwift

final class WindowLevelCalculatorTests: XCTestCase {
    func testPresetsForCT() {
        let calc = WindowLevelCalculator()
        let presets = calc.getPresets(for: .ct)
        XCTAssertTrue(presets.contains { $0.name == "Abdomen" && $0.windowWidth == 350 && $0.windowLevel == 40 })
    }

    func testDefaultWindowLevel() {
        let calc = WindowLevelCalculator()
        let defaults = calc.defaultWindowLevel(for: .mr)
        XCTAssertEqual(defaults.level, 300)
        XCTAssertEqual(defaults.width, 600)
    }

    func testContextConversions() {
        let context = DicomImageContext(
            windowWidths: [400],
            windowCenters: [40],
            currentWindowWidth: 400,
            currentWindowCenter: 40,
            rescaleSlope: 2.0,
            rescaleIntercept: 10.0
        )
        let calc = WindowLevelCalculator()
        let pixel = calc.calculateWindowLevel(context: context)
        XCTAssertEqual(pixel.pixelWidth, 200)
        XCTAssertEqual(pixel.pixelLevel, 15)

        let hu = calc.convertPixelToHU(pixelValue: 50, context: context)
        XCTAssertEqual(hu, 110)

        let px = calc.convertHUToPixel(huValue: 110, context: context)
        XCTAssertEqual(px, 50)
    }

    static var allTests = [
        ("testPresetsForCT", testPresetsForCT),
        ("testDefaultWindowLevel", testDefaultWindowLevel),
        ("testContextConversions", testContextConversions)
    ]
}

