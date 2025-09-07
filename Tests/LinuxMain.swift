import XCTest

import DcmSwiftTests

var tests = [XCTestCaseEntry]()
tests += DcmSwiftTests.allTests()
tests += WindowLevelCalculatorTests.allTests()
XCTMain(tests)
