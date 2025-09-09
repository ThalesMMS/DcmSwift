import XCTest
@testable import DcmSwift

final class PixelStreamingTests: XCTestCase {
    func testStreamPixelFragments() {
        let fragmentCount = 3
        let fragmentSize = 1024 * 1024 // 1MB each

        var data = Data()
        // Pixel Data tag (7fe0,0010) with OB VR and undefined length
        data.append(contentsOf: [0xe0, 0x7f, 0x10, 0x00])
        data.append(contentsOf: [0x4f, 0x42]) // "OB"
        data.append(contentsOf: [0x00, 0x00])
        data.append(contentsOf: [0xff, 0xff, 0xff, 0xff])

        for _ in 0..<fragmentCount {
            // Item tag FFFE,E000
            data.append(contentsOf: [0xfe, 0xff, 0x00, 0xe0])
            // Length
            let len = UInt32(fragmentSize)
            data.append(contentsOf: [UInt8(len & 0xff), UInt8((len >> 8) & 0xff), UInt8((len >> 16) & 0xff), UInt8((len >> 24) & 0xff)])
            data.append(Data(repeating: 0x00, count: fragmentSize))
        }

        // Sequence delimiter FFFE,E0DD
        data.append(contentsOf: [0xfe, 0xff, 0xdd, 0xe0])
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])

        let dis = DicomInputStream(data: data)
        dis.open()

        var count = 0
        var bytes = 0
        dis.readPixelDataFragments { fragment in
            count += 1
            bytes += fragment.count
            return true
        }

        XCTAssertEqual(count, fragmentCount)
        XCTAssertEqual(bytes, fragmentCount * fragmentSize)
        dis.close()
    }

    static var allTests = [
        ("testStreamPixelFragments", testStreamPixelFragments),
    ]
}

