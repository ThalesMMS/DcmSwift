import XCTest
@testable import DcmSwift

final class ConcurrentWindowingTests: XCTestCase {
    func testApplyWindow8MatchesSequential() async throws {
        let width = 2000
        let height = 1200
        let count = width * height
        let winMin = 50
        let winMax = 200
        let src = (0..<count).map { UInt8($0 % 255) }
        var dst = [UInt8](repeating: 0, count: count)
        try await applyWindowTo8Concurrent(src: src,
                                           width: width,
                                           height: height,
                                           winMin: winMin,
                                           winMax: winMax,
                                           into: &dst)
        var baseline = [UInt8](repeating: 0, count: count)
        let denom = max(winMax - winMin, 1)
        for i in 0..<count {
            let v = Int(src[i])
            let clamped = min(max(v - winMin, 0), denom)
            baseline[i] = UInt8(clamped * 255 / denom)
        }
        XCTAssertEqual(dst, baseline)
    }

    func testApplyWindow8Cancellation() async {
        let width = 2000
        let height = 1200
        let count = width * height
        let src = (0..<count).map { UInt8($0 % 255) }
        var dst = [UInt8](repeating: 0, count: count)
        let task = Task {
            try await applyWindowTo8Concurrent(src: src,
                                               width: width,
                                               height: height,
                                               winMin: 0,
                                               winMax: 255,
                                               into: &dst)
        }
        task.cancel()
        do {
            try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testApplyLUT16MatchesSequential() async throws {
        let width = 1500
        let height = 1500
        let count = width * height
        let src = (0..<count).map { UInt16($0 % 65535) }
        var dst = [UInt8](repeating: 0, count: count)
        var lut = [UInt8](repeating: 0, count: 65536)
        for i in 0..<65536 { lut[i] = UInt8(i % 256) }
        try await applyLUTTo16Concurrent(src: src,
                                         width: width,
                                         height: height,
                                         lut: lut,
                                         into: &dst)
        var baseline = [UInt8](repeating: 0, count: count)
        for i in 0..<count { baseline[i] = lut[Int(src[i])] }
        XCTAssertEqual(dst, baseline)
    }

    static var allTests = [
        ("testApplyWindow8MatchesSequential", testApplyWindow8MatchesSequential),
        ("testApplyWindow8Cancellation", testApplyWindow8Cancellation),
        ("testApplyLUT16MatchesSequential", testApplyLUT16MatchesSequential)
    ]
}

