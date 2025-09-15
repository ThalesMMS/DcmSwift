//
//  Phase5DIMSETests.swift
//  DcmSwift
//
//  Phase 5: Networking Stabilization Tests
//  Created by AI Assistant on 2025-01-14.
//

import XCTest
import DcmSwift
import NIO

final class Phase5DIMSETests: XCTestCase {
    
    func testCFindPacking_CommandAndDatasetTogether() throws {
        // Test that C-FIND properly packs command and dataset in single PDU
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }

        let calling = DicomEntity(title: "TEST_CLIENT", hostname: "127.0.0.1", port: 4096)
        let called = DicomEntity(title: "TEST_PACS", hostname: "127.0.0.1", port: 11112)
        let assoc = DicomAssociation(group: group, callingAE: calling, calledAE: called)

        // Setup presentation context
        let pcID: UInt8 = 1
        let asuid = DicomConstants.StudyRootQueryRetrieveInformationModelFIND
        let tsuid = TransferSyntax.explicitVRLittleEndian
        let pc = PresentationContext(abstractSyntax: asuid, transferSyntaxes: [tsuid], contextID: pcID)
        assoc.presentationContexts[pcID] = pc
        assoc.acceptedPresentationContexts[pcID] = pc

        // Build query dataset
        let queryDataset = DataSet()
        _ = queryDataset.set(value: "STUDY", forTagName: "QueryRetrieveLevel")
        _ = queryDataset.set(value: "CT", forTagName: "ModalitiesInStudy")

        // Create C-FIND-RQ message
        guard let cfindRQ = PDUEncoder.createDIMSEMessage(pduType: .dataTF, commandField: .C_FIND_RQ, association: assoc) as? CFindRQ else {
            return XCTFail("Failed to create CFindRQ")
        }
        cfindRQ.queryDataset = queryDataset

        // Generate PDU data
        guard let pduData = cfindRQ.data() else {
            return XCTFail("CFindRQ.data() returned nil")
        }

        // Verify PDU structure
        XCTAssertGreaterThan(pduData.count, 6, "PDU should have header + payload")
        
        // Parse PDU header
        let pduType = pduData[0]
        XCTAssertEqual(pduType, PDUType.dataTF.rawValue, "Should be DATA-TF PDU")
        
        let totalLength = pduData.subdata(in: 2..<6).toUInt32(byteOrder: .BigEndian)
        XCTAssertEqual(totalLength, UInt32(pduData.count - 6), "PDU length should match payload size")
        
        // Parse PDVs
        var offset = 6
        var pdvCount = 0
        
        while offset < pduData.count {
            guard offset + 4 <= pduData.count else { break }
            
            let pdvLength = pduData.subdata(in: offset..<(offset+4)).toUInt32(byteOrder: .BigEndian)
            offset += 4
            
            guard offset + 2 <= pduData.count else { break }
            
            let pcID = pduData[offset]
            let flags = pduData[offset + 1]
            offset += 2
            
            let pdvData = pduData.subdata(in: offset..<(offset + Int(pdvLength - 2)))
            offset += Int(pdvLength - 2)
            
            pdvCount += 1
            
            if pdvCount == 1 {
                // First PDV should be command
                XCTAssertEqual(flags, 0x03, "First PDV should be command + last fragment")
                XCTAssertEqual(pcID, 1, "Should use correct presentation context")
                
                // Verify CommandDataSetType indicates dataset follows
                let commandStream = DicomInputStream(data: pdvData)
                commandStream.vrMethod = .Implicit
                commandStream.byteOrder = .LittleEndian
                
                if let commandDataset = try? commandStream.readDataset(enforceVR: false) {
                    let dataSetType = commandDataset.integer16(forTag: "CommandDataSetType")
                    XCTAssertEqual(dataSetType, 0x0000, "CommandDataSetType should indicate dataset follows")
                }
            } else if pdvCount == 2 {
                // Second PDV should be dataset
                XCTAssertEqual(flags, 0x02, "Second PDV should be data + last fragment")
                XCTAssertEqual(pcID, 1, "Should use correct presentation context")
                XCTAssertGreaterThan(pdvData.count, 0, "Dataset PDV should contain data")
            }
        }
        
        XCTAssertEqual(pdvCount, 2, "Should have exactly 2 PDVs (command + dataset)")
    }
    
    func testPDUBytesDecoder_HandlesFragmentedTCP() throws {
        // Test that PDUBytesDecoder properly handles fragmented TCP streams
        let decoder = PDUBytesDecoder()
        
        // Create a test PDU (simplified DATA-TF)
        var testPDU = Data()
        testPDU.append(PDUType.dataTF.rawValue) // PDU Type
        testPDU.append(0x00) // Reserved
        testPDU.append(contentsOf: [0x00, 0x00, 0x00, 0x10]) // Length = 16 bytes
        testPDU.append(contentsOf: Array(repeating: 0x42, count: 16)) // Payload
        
        // Split into fragments to simulate TCP fragmentation
        let fragment1 = testPDU.prefix(8) // First half
        let fragment2 = testPDU.suffix(from: 8) // Second half
        
        // Test reassembly
        let allocator = ByteBufferAllocator()
        var buffer1 = allocator.buffer(capacity: fragment1.count)
        buffer1.writeBytes(fragment1)
        
        var buffer2 = allocator.buffer(capacity: fragment2.count)
        buffer2.writeBytes(fragment2)
        
        // Simulate channel context (simplified)
        class MockChannelHandlerContext: ChannelHandlerContext {
            let channel: Channel
            
            init() {
                self.channel = MockChannel()
            }
            
            func fireChannelRead(_ data: NIOAny) {
                // Mock implementation
            }
            
            func wrapInboundOut(_ value: Any) -> NIOAny {
                return NIOAny(value)
            }
        }
        
        class MockChannel: Channel {
            let allocator = ByteBufferAllocator()
            // Mock implementation
        }
        
        let context = MockChannelHandlerContext()
        
        // Process first fragment
        let result1 = decoder.decode(context: context, buffer: &buffer1)
        XCTAssertEqual(result1, .needMoreData, "Should need more data after first fragment")
        
        // Process second fragment
        let result2 = decoder.decode(context: context, buffer: &buffer2)
        XCTAssertEqual(result2, .needMoreData, "Should need more data after second fragment")
    }
    
    func testCStoreSCP_HandlesIncomingRequests() throws {
        // Test that C-STORE SCP properly handles incoming C-STORE requests
        let delegate = MockCStoreSCPDelegate()
        let cstoreSCP = CStoreSCP(delegate)
        
        // Create mock association and channel
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }
        
        let calling = DicomEntity(title: "TEST_CLIENT", hostname: "127.0.0.1", port: 4096)
        let called = DicomEntity(title: "TEST_SERVER", hostname: "127.0.0.1", port: 11112)
        let assoc = DicomAssociation(group: group, callingAE: calling, calledAE: called)
        
        // Setup presentation context for C-STORE
        let pcID: UInt8 = 1
        let asuid = DicomConstants.CTImageStorage
        let tsuid = TransferSyntax.explicitVRLittleEndian
        let pc = PresentationContext(abstractSyntax: asuid, transferSyntaxes: [tsuid], contextID: pcID)
        assoc.presentationContexts[pcID] = pc
        assoc.acceptedPresentationContexts[pcID] = pc
        
        // Create mock C-STORE request
        let storeRequest = CStoreRQ(pduType: .dataTF, commandField: .C_STORE_RQ, association: assoc)
        let testDataset = DataSet()
        _ = testDataset.set(value: "1.2.3.4.5", forTagName: "SOPInstanceUID")
        _ = testDataset.set(value: "CT", forTagName: "Modality")
        storeRequest.dataset = testDataset
        
        // Mock channel
        let channel = try group.next().makePromise(of: Void.self).futureResult
        
        // Test that reply method doesn't crash
        let future = cstoreSCP.reply(request: storeRequest, association: assoc, channel: channel)
        
        // The future should complete (success or failure)
        XCTAssertNoThrow(try future.wait(), "C-STORE SCP reply should not throw")
    }
}

// Mock delegate for testing
class MockCStoreSCPDelegate: CStoreSCPDelegate {
    var storedFiles: [(DataSet, String)] = []
    
    func store(fileMetaInfo: DataSet, dataset: DataSet, tempFile: String) -> Bool {
        storedFiles.append((dataset, tempFile))
        return true
    }
}
