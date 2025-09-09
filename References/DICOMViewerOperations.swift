//
//  DICOMViewerOperations.swift
//  DICOMViewer
//
//  Swift protocol for DICOM viewer operations
//  Replacing DICOMViewerOperations.h
//  Created by Swift Migration on 2025-08-28.
//  Copyright © 2025 DICOM Viewer. All rights reserved.
//

import UIKit
import Foundation

// MARK: - Main Operations Protocol

/// Protocol defining DICOM viewer operations for OptionsPanel interaction
/// Modern Swift version of the Objective-C DICOMViewerOperations protocol
@objc protocol DICOMViewerOperations: NSObjectProtocol {
    
    // MARK: - Window/Level Control
    
    /// Apply a window/level preset to the current DICOM image
    /// - Parameter preset: The preset to apply
    @objc func applyWindowLevelPreset(_ preset: WindowLevelPreset)
    
    /// Set custom window/level values
    /// - Parameters:
    ///   - windowWidth: The window width value
    ///   - windowCenter: The window center value
    @objc func setWindowWidth(_ windowWidth: Double, windowCenter: Double)
    
    /// Get current window/level values
    /// - Parameters:
    ///   - windowWidth: Pointer to store current window width
    ///   - windowCenter: Pointer to store current window center
    @objc func getCurrentWindowWidth(_ windowWidth: UnsafeMutablePointer<Double>, 
                                    windowCenter: UnsafeMutablePointer<Double>)
    
    // MARK: - Image Transformation
    
    /// Rotate the image by specified degrees
    /// - Parameter degrees: Rotation angle (90, -90, 180, etc.)
    @objc func rotateImage(byDegrees degrees: CGFloat)
    
    /// Flip the image horizontally
    @objc func flipImageHorizontally()
    
    /// Flip the image vertically
    @objc func flipImageVertically()
    
    /// Reset all transformations to original state
    @objc func resetImageTransformations()
    
    // MARK: - Cine Playback Control
    
    /// Check if multiple images are available for cine playback
    @objc func hasMultipleImages() -> Bool
    
    /// Start/stop cine playback
    /// - Parameter playing: true to start, false to stop
    @objc func setCinePlayback(_ playing: Bool)
    
    /// Set cine playback speed
    /// - Parameter speed: Speed multiplier (0.5, 1.0, 2.0, etc.)
    @objc func setCineSpeed(_ speed: CGFloat)
    
    /// Check current cine playback state
    @objc func isCinePlaying() -> Bool
    
    // MARK: - DICOM Metadata Access
    
    /// Get patient information from DICOM tags
    @objc func getPatientInfo() -> [String: Any]
    
    /// Get study information from DICOM tags
    @objc func getStudyInfo() -> [String: Any]
    
    /// Get series information from DICOM tags
    @objc func getSeriesInfo() -> [String: Any]
    
    /// Get image properties from DICOM tags
    @objc func getImageProperties() -> [String: Any]
}

// MARK: - Swift-Only Protocol Extensions

/// Swift-native operations protocol for @MainActor ViewModels
/// This is the Swift 6 compliant version that @MainActor classes can conform to
@MainActor
protocol SwiftDICOMViewerOperations {
    
    // MARK: - Window/Level Control
    
    /// Apply a window/level preset to the current DICOM image
    func applyWindowLevelPreset(_ preset: WindowLevelPreset)
    
    /// Set custom window/level values
    func setWindowWidth(_ windowWidth: Double, windowCenter: Double)
    
    /// Get window/level values as a tuple (Swift-friendly)
    func getCurrentWindowLevel() -> (width: Double, center: Double)
    
    // MARK: - Image Transformation
    
    /// Rotate the image by specified degrees
    func rotateImage(byDegrees degrees: CGFloat)
    
    /// Flip the image horizontally
    func flipImageHorizontally()
    
    /// Flip the image vertically
    func flipImageVertically()
    
    /// Reset all transformations to original state
    func resetImageTransformations()
    
    // MARK: - Multi-Image Support
    
    /// Check if multiple images are available
    func hasMultipleImages() -> Bool
    
    // MARK: - Swift-Specific Extensions
    
    /// Apply transform with animation
    func applyTransform(_ transform: CGAffineTransform, animated: Bool)
    
    /// Get all metadata as a structured type
    func getAllMetadata() -> DICOMMetadata
    
    /// Async version for loading operations
    func loadDICOMFile(at url: URL) async throws
    
    /// Export current view as image
    func exportCurrentView() -> UIImage?
}

// MARK: - Supporting Data Structures

/// Structured metadata for DICOM files
struct DICOMMetadata {
    let patient: PatientInfo
    let study: StudyInfo
    let series: SeriesInfo
    let image: ImageProperties
    
    struct PatientInfo {
        let name: String?
        let id: String?
        let birthDate: Date?
        let sex: String?
        let age: String?
    }
    
    struct StudyInfo {
        let id: String?
        let date: Date?
        let description: String?
        let accessionNumber: String?
        let institutionName: String?
    }
    
    struct SeriesInfo {
        let number: String?
        let description: String?
        let modality: String?
        let bodyPart: String?
        let instanceCount: Int
    }
    
    struct ImageProperties {
        let width: Int
        let height: Int
        let bitsPerPixel: Int
        let photometricInterpretation: String?
        let pixelSpacing: (x: Double, y: Double)?
        let sliceThickness: Double?
        let imagePosition: (x: Double, y: Double, z: Double)?
    }
}

// MARK: - Default Protocol Implementations

extension SwiftDICOMViewerOperations {
    
    /// Default implementation for window/level tuple getter
    func getCurrentWindowLevel() -> (width: Double, center: Double) {
        // Default implementation - should be overridden by conforming types
        return (400, 0)
    }
    
    /// Default implementation for animated transforms
    func applyTransform(_ transform: CGAffineTransform, animated: Bool) {
        // Default implementation - should be overridden by conforming types
        if animated {
            UIView.animate(withDuration: 0.3) {
                // Apply transform to view
            }
        }
    }
    
    /// Default implementation for metadata
    func getAllMetadata() -> DICOMMetadata {
        // Default empty metadata
        return DICOMMetadata(
            patient: DICOMMetadata.PatientInfo(name: nil, id: nil, birthDate: nil, sex: nil, age: nil),
            study: DICOMMetadata.StudyInfo(id: nil, date: nil, description: nil, accessionNumber: nil, institutionName: nil),
            series: DICOMMetadata.SeriesInfo(number: nil, description: nil, modality: nil, bodyPart: nil, instanceCount: 0),
            image: DICOMMetadata.ImageProperties(width: 0, height: 0, bitsPerPixel: 16, photometricInterpretation: nil, pixelSpacing: nil, sliceThickness: nil, imagePosition: nil)
        )
    }
    
    /// Default implementation for async file loading
    func loadDICOMFile(at url: URL) async throws {
        // Default implementation - should be overridden by conforming types
        throw DICOMError.fileNotFound(path: url.path)
    }
    
    /// Default implementation for export
    func exportCurrentView() -> UIImage? {
        // Default implementation - should be overridden by conforming types
        return nil
    }
}

// MARK: - Objective-C Bridge Implementation

/// Bridge class for Objective-C compatibility
@objc(DICOMViewerOperationsBridge)
class DICOMViewerOperationsBridge: NSObject {
    
    /// Check if a class conforms to the DICOMViewerOperations protocol
    @objc static func checkConformance(_ object: Any) -> Bool {
        return object is DICOMViewerOperations
    }
    
    /// Create a type-safe wrapper for Objective-C objects
    @objc static func wrap(_ object: Any) -> DICOMViewerOperations? {
        return object as? DICOMViewerOperations
    }
}