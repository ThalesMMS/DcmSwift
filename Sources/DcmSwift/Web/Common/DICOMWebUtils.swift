//
//  DICOMWebUtils.swift
//  DcmSwift
//
//  Created by Thales on 2025/01/05.
//

import Foundation

/// Utility functions for DICOMweb operations
public struct DICOMWebUtils {
    
    /// Extracts Study Instance UID from a WADO-RS URL
    /// Example: /studies/1.2.3.4/series/5.6.7.8 -> 1.2.3.4
    public static func extractStudyUID(from url: String) -> String? {
        let components = url.components(separatedBy: "/")
        if let studyIndex = components.firstIndex(of: "studies"),
           studyIndex + 1 < components.count {
            return components[studyIndex + 1]
        }
        return nil
    }
    
    /// Extracts Series Instance UID from a WADO-RS URL
    /// Example: /studies/1.2.3.4/series/5.6.7.8 -> 5.6.7.8
    public static func extractSeriesUID(from url: String) -> String? {
        let components = url.components(separatedBy: "/")
        if let seriesIndex = components.firstIndex(of: "series"),
           seriesIndex + 1 < components.count {
            return components[seriesIndex + 1]
        }
        return nil
    }
    
    /// Extracts Instance UID from a WADO-RS URL
    /// Example: /studies/1.2.3.4/series/5.6.7.8/instances/9.10.11.12 -> 9.10.11.12
    public static func extractInstanceUID(from url: String) -> String? {
        let components = url.components(separatedBy: "/")
        if let instanceIndex = components.firstIndex(of: "instances"),
           instanceIndex + 1 < components.count {
            return components[instanceIndex + 1]
        }
        return nil
    }
    
    /// Builds query parameters string from dictionary
    /// Example: ["PatientID": "12345", "StudyDate": "20240101"] -> "?PatientID=12345&StudyDate=20240101"
    public static func buildQueryString(from parameters: [String: String]) -> String {
        guard !parameters.isEmpty else { return "" }
        
        let queryItems = parameters.map { key, value in
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(key)=\(encodedValue)"
        }
        
        return "?" + queryItems.joined(separator: "&")
    }
    
    /// Formats a Date for DICOM query (YYYYMMDD format)
    public static func formatDicomDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        return formatter.string(from: date)
    }
    
    /// Formats a date range for DICOM query
    /// Example: (startDate, endDate) -> "20240101-20240131"
    public static func formatDicomDateRange(from startDate: Date, to endDate: Date) -> String {
        let start = formatDicomDate(startDate)
        let end = formatDicomDate(endDate)
        return "\(start)-\(end)"
    }
    
    /// Generates a random boundary string for multipart encoding
    public static func generateBoundary() -> String {
        return UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }
    
    /// Extracts boundary from Content-Type header
    /// Example: "multipart/related; boundary=abc123" -> "abc123"
    public static func extractBoundary(from contentType: String) -> String? {
        let components = contentType.components(separatedBy: ";")
        for component in components {
            let trimmed = component.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("boundary=") {
                let boundary = trimmed.dropFirst("boundary=".count)
                // Remove quotes if present
                return boundary.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }
        return nil
    }
    
    /// Validates a DICOM UID format
    public static func isValidUID(_ uid: String) -> Bool {
        // DICOM UIDs can only contain digits and dots
        // Must not start or end with a dot
        // Must not have consecutive dots
        // Maximum length is 64 characters
        
        guard !uid.isEmpty && uid.count <= 64 else { return false }
        guard !uid.hasPrefix(".") && !uid.hasSuffix(".") else { return false }
        guard !uid.contains("..") else { return false }
        
        let allowedCharacters = CharacterSet(charactersIn: "0123456789.")
        return uid.rangeOfCharacter(from: allowedCharacters.inverted) == nil
    }
}