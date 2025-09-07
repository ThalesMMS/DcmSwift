import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(DcmSwiftTests.allTests),
        testCase(WindowLevelCalculatorTests.allTests),
    ]
}
#endif
