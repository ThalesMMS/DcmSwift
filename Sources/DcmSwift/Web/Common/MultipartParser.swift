import Foundation

/// Parser for multipart/related HTTP responses
/// Based on the JavaScript implementation in dicomweb-client/src/message.js  
/// Reference: DICOM PS3.18 Section 10.4.1.2
public struct MultipartParser {
    
    /// Parses a multipart/related response and returns the binary parts
    /// - Parameters:
    ///   - data: The complete multipart response data
    ///   - boundary: The boundary string from Content-Type header
    /// - Returns: Array of Data objects, one for each part's binary content
    /// - Throws: DICOMWebError if parsing fails
    public static func parse(data: Data, boundary: String) throws -> [Data] {
        // Prepare delimiters as Data for efficient binary searching
        let lineBreak = "\r\n".data(using: .utf8)!
        let boundaryDelimiter = "--\(boundary)".data(using: .utf8)!
        let finalBoundaryDelimiter = "--\(boundary)--".data(using: .utf8)!
        let headerSeparator = "\r\n\r\n".data(using: .utf8)!
        
        // Initialize result array and current position
        var parts: [Data] = []
        var currentIndex = 0
        
        // Find the first boundary to start parsing
        guard let firstBoundaryRange = data.range(of: boundaryDelimiter, in: currentIndex..<data.count) else {
            throw DICOMWebError.invalidMultipartResponse("No boundary found in multipart response")
        }
        
        // Move past the first boundary and its line break
        currentIndex = firstBoundaryRange.upperBound
        if currentIndex + lineBreak.count <= data.count,
           data.subdata(in: currentIndex..<currentIndex + lineBreak.count) == lineBreak {
            currentIndex += lineBreak.count
        }
        
        // Main parsing loop
        while currentIndex < data.count {
            // Check if we've reached the final boundary
            if currentIndex + finalBoundaryDelimiter.count <= data.count,
               data.subdata(in: currentIndex..<currentIndex + finalBoundaryDelimiter.count) == finalBoundaryDelimiter {
                // We've reached the end
                break
            }
            
            // Find the next boundary (either regular or final)
            var nextBoundaryRange: Range<Int>?
            
            // Look for the next regular boundary
            if let regularBoundaryRange = data.range(of: boundaryDelimiter, in: currentIndex..<data.count) {
                nextBoundaryRange = regularBoundaryRange
            }
            
            // Check if there's a final boundary before the regular one
            if let finalRange = data.range(of: finalBoundaryDelimiter, in: currentIndex..<data.count) {
                if nextBoundaryRange == nil || finalRange.lowerBound < nextBoundaryRange!.lowerBound {
                    nextBoundaryRange = finalRange
                }
            }
            
            guard let boundaryRange = nextBoundaryRange else {
                // No more boundaries found - this is an error
                throw DICOMWebError.invalidMultipartResponse("Malformed multipart: missing closing boundary")
            }
            
            // The part ends just before the line break that precedes the boundary
            // Boundaries are always preceded by \r\n
            let partEndIndex = boundaryRange.lowerBound - lineBreak.count
            
            // Find the header/body separator within this part
            guard let headerEndRange = data.range(of: headerSeparator, in: currentIndex..<partEndIndex) else {
                throw DICOMWebError.invalidMultipartResponse("Part missing header/body separator")
            }
            
            // Extract the body (we don't need headers for binary DICOM data)
            let bodyStartIndex = headerEndRange.upperBound
            let bodyData = data.subdata(in: bodyStartIndex..<partEndIndex)
            
            // Add this part's body to our results
            parts.append(bodyData)
            
            // Move to the next part (past the boundary and its line break)
            currentIndex = boundaryRange.upperBound
            if currentIndex + lineBreak.count <= data.count,
               data.subdata(in: currentIndex..<currentIndex + lineBreak.count) == lineBreak {
                currentIndex += lineBreak.count
            }
        }
        
        return parts
    }
    
    /// Extracts the boundary string from a Content-Type header
    /// - Parameter contentType: The Content-Type header value
    /// - Returns: The boundary string if found, nil otherwise
    public static func extractBoundary(from contentType: String) -> String? {
        // Look for boundary parameter in Content-Type header
        // Format: multipart/related; boundary=xxx or boundary="xxx"
        
        let components = contentType.components(separatedBy: ";")
        for component in components {
            let trimmed = component.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("boundary=") {
                var boundary = trimmed.dropFirst("boundary=".count)
                // Remove quotes if present
                if boundary.hasPrefix("\"") && boundary.hasSuffix("\"") {
                    boundary = boundary.dropFirst().dropLast()
                }
                return String(boundary)
            }
        }
        
        return nil
    }
}