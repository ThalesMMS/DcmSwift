import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(DcmSwiftTests.allTests),
        testCase(WindowLevelCalculatorTests.allTests),
        #if canImport(Network)
        testCase(PixelStreamingTests.allTests),
        #endif
        testCase(ConcurrentWindowingTests.allTests),
    ]
}
#endif
