//
//  PDUMessageDecoder.swift
//  
//
//  Created by Rafael Warnault, OPALE on 14/07/2021.
//

import Foundation
import NIO

/**
 The `PDUBytesDecoder` is a `ByteToMessageDecoder` subclass used by the SwiftNIO channel pipeline
 to handle the continuous stream of bytes from a TCP connection. It is responsible for parsing and
 reassembling DICOM PDU (Protocol Data Unit) structures from the byte stream.

 This decoder operates as a simple state machine to solve the TCP fragmentation problem. It reads the
 PDU header to determine the total length of the incoming message, and then waits until it has received
 all the necessary bytes before passing the complete PDU message up to the next channel handler
 (in this case, `DicomAssociation`).

 The process is as follows:
 1. Read the first 6 bytes of the PDU header, which include the PDU type and length.
 2. From the header, extract the `pduLength`, which specifies the length of the rest of the message.
 3. Check if the buffer contains at least `pduLength` more bytes.
 4. If it does, read that segment, assemble the complete PDU, and pass it to the next handler.
 5. If it doesn't, return `.needMoreData` and wait for more bytes to arrive on the socket.
 */
public class PDUBytesDecoder: ByteToMessageDecoder {
    public typealias InboundOut = ByteBuffer
    
    // Internal buffer to accumulate data across multiple reads
    private var internalBuffer: ByteBuffer?
    
    public init() { }

    public func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) -> DecodingState {
        // Append the new data to our internal buffer
        if internalBuffer == nil {
            internalBuffer = context.channel.allocator.buffer(capacity: buffer.readableBytes)
        }
        internalBuffer?.writeBuffer(&buffer)
        
        // Loop to process as many complete PDUs as we have in the buffer
        while let pdu = try? parsePDU(from: &internalBuffer!) {
            context.fireChannelRead(self.wrapInboundOut(pdu))
        }
        
        // If there's no more data to process, discard the buffer if it's empty
        if internalBuffer?.readableBytes == 0 {
            internalBuffer = nil
        }
        
        return .needMoreData
    }
    
    private func parsePDU(from buffer: inout ByteBuffer) throws -> ByteBuffer? {
        // The PDU header is 6 bytes (1 for type, 1 reserved, 4 for length).
        guard buffer.readableBytes >= 6 else {
            return nil
        }
        
        // Peek at the length without moving the reader index.
        // Bytes at indices 2-5 represent the PDU length.
        let pduLength = Int(buffer.getInteger(at: buffer.readerIndex + 2, as: UInt32.self) ?? 0)
        
        // Now we have the length, check if the full PDU is available.
        // The total message size is the header (6 bytes) + the PDU length.
        let fullPduSize = 6 + pduLength
        guard buffer.readableBytes >= fullPduSize else {
            return nil
        }
        
        // The full PDU is in the buffer, so we can now read it.
        return buffer.readSlice(length: fullPduSize)
    }
    
    public func decodeLast(context: ChannelHandlerContext, buffer: inout ByteBuffer, seenEOF: Bool) throws -> DecodingState {
        // Try to decode any remaining bytes if the channel is closing.
        _ = try self.decode(context: context, buffer: &buffer)
        
        if buffer.readableBytes > 0 {
            // This indicates leftover data that doesn't form a complete PDU.
            // Depending on the protocol, this might be an error.
            // For now, we'll just log it or handle as needed.
            print("Warning: Leftover bytes in buffer at EOF: \(buffer.readableBytes)")
        }
        
        // Discard any remaining data in the internal buffer
        self.internalBuffer = nil
        
        return .needMoreData
    }
}