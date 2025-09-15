//  DicomPixelViewIntegrationTests.swift
// 
//  DcmSwift
//
//  Created by Thales on 2025/09/10.
// 

#if canImport(UIKit)
import XCTest
@testable import DcmSwift

final class DicomPixelViewIntegrationTests: XCTestCase {
    func testGrayscalePipeline() {
        let view = DicomPixelView(frame: .zero)
        let pixels: [UInt8] = [0, 64, 128, 255]
        view.setPixels8(pixels, width: 2, height: 2, windowWidth: 255, windowCenter: 128)
        XCTAssertGreaterThan(view.estimatedMemoryUsage(), 0)
    }

    func testRGBPipeline() {
        let view = DicomPixelView(frame: .zero)
        let pixels: [UInt8] = [255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 255]
        view.setPixelsRGB(pixels, width: 2, height: 2)
        XCTAssertGreaterThan(view.estimatedMemoryUsage(), 0)
    }
}
#endif
