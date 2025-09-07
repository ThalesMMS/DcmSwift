//
//  ROIMeasurementService.swift
//  DICOMViewer
//
//  ROI measurement service for distance and ellipse measurements
//  Extracted from SwiftDetailViewController for Phase 6B
//

public import UIKit
public import Foundation

// MARK: - Protocol Definitions

/// Protocol for ROI measurement tools interaction
public protocol ROIMeasurementToolsProtocol {
    func activateDistanceMeasurement()
    func activateEllipseMeasurement()
}

// MARK: - Data Models

public enum ROIMeasurementMode: String, CaseIterable, Sendable {
    case none = "none"
    case distance = "distance"
    case ellipse = "ellipse"
}

public struct ROIMeasurementData: Sendable {
    let id: UUID
    let type: ROIMeasurementMode
    let points: [CGPoint]
    let value: String
    let pixelSpacing: PixelSpacing
    let boundingRect: CGRect
    
    init(type: ROIMeasurementMode, points: [CGPoint], value: String, pixelSpacing: PixelSpacing) {
        self.id = UUID()
        self.type = type
        self.points = points
        self.value = value
        self.pixelSpacing = pixelSpacing
        self.boundingRect = points.reduce(.null) { result, point in
            result.union(CGRect(origin: point, size: CGSize(width: 1, height: 1)))
        }
    }
}

public struct MeasurementResetResult: Sendable {
    let shouldEnableWindowLevel: Bool
    let newMode: ROIMeasurementMode
}

public struct MeasurementResult: Sendable {
    let measurement: ROIMeasurementData
    let displayValue: String
    let rawValue: Double
}

// MARK: - Protocol Definition

@MainActor
public protocol ROIMeasurementServiceProtocol {
    func startDistanceMeasurement(at point: CGPoint)
    func startEllipseMeasurement(at point: CGPoint)
    func addMeasurementPoint(_ point: CGPoint)
    func completeMeasurement() -> MeasurementResult?
    func calculateDistance(from: CGPoint, to: CGPoint, pixelSpacing: PixelSpacing) -> Double
    func calculateDistanceFromViewCoordinates(viewPoint1: CGPoint, viewPoint2: CGPoint, dicomView: UIView, imageWidth: Int, imageHeight: Int, pixelSpacing: PixelSpacing) -> (distance: Double, pixelPoints: (CGPoint, CGPoint))
    func calculateEllipseArea(points: [CGPoint], pixelSpacing: PixelSpacing) -> Double
    func calculateEllipseDensityFromViewCoordinates(centerView: CGPoint, edgeView: CGPoint, dicomView: UIView, imageWidth: Int, imageHeight: Int, pixelData: Data?, rescaleSlope: Double, rescaleIntercept: Double) -> (averageHU: Double, pixelCount: Int, centerPixel: CGPoint, radiusPixel: Double)?
    func calculateHUDensity(at point: CGPoint, pixelData: Data?, width: Int, height: Int) -> Double?
    func convertToImagePixelPoint(_ viewPoint: CGPoint, in dicomView: UIView, imageWidth: Int, imageHeight: Int) -> CGPoint
    func clearAllMeasurements()
    func clearAllMeasurements(from overlays: inout [CAShapeLayer], labels: inout [UILabel], currentOverlay: inout CAShapeLayer?)
    func clearCompletedMeasurements<T>(_ completedMeasurements: inout [T]) where T: AnyObject
    func resetMeasurementState() -> MeasurementResetResult
    func clearMeasurement(withId id: UUID)
    func isValidMeasurement() -> Bool
    
    var currentMeasurementMode: ROIMeasurementMode { get set }
    var activeMeasurementPoints: [CGPoint] { get }
    var measurements: [ROIMeasurementData] { get }
}

// MARK: - Service Implementation

@MainActor
public final class ROIMeasurementService: ROIMeasurementServiceProtocol {
    
    // MARK: - Properties
    
    public var currentMeasurementMode: ROIMeasurementMode = .none
    public private(set) var activeMeasurementPoints: [CGPoint] = []
    public private(set) var measurements: [ROIMeasurementData] = []
    
    private var currentPixelSpacing: PixelSpacing = .unknown
    // DCMDecoder removed - using DcmSwift
    
    // MARK: - Singleton
    
    public static let shared = ROIMeasurementService()
    private init() {}
    
    // MARK: - Public Methods
    
    public func startDistanceMeasurement(at point: CGPoint) {
        currentMeasurementMode = .distance
        activeMeasurementPoints = [point]
        print("[ROI] Started distance measurement at: \(point)")
    }
    
    public func startEllipseMeasurement(at point: CGPoint) {
        currentMeasurementMode = .ellipse
        activeMeasurementPoints = [point]
        print("[ROI] Started ellipse measurement at: \(point)")
    }
    
    public func addMeasurementPoint(_ point: CGPoint) {
        guard currentMeasurementMode != .none else { return }
        
        switch currentMeasurementMode {
        case .distance:
            if activeMeasurementPoints.count < 2 {
                activeMeasurementPoints.append(point)
            } else {
                // Replace the last point for real-time feedback
                activeMeasurementPoints[1] = point
            }
            
        case .ellipse:
            // For ellipse, we collect multiple points to define the ellipse
            activeMeasurementPoints.append(point)
            
        case .none:
            break
        }
    }
    
    public func completeMeasurement() -> MeasurementResult? {
        guard isValidMeasurement() else { return nil }
        
        switch currentMeasurementMode {
        case .distance:
            return completeDistanceMeasurement()
        case .ellipse:
            return completeEllipseMeasurement()
        case .none:
            return nil
        }
    }
    
    public func calculateDistance(from startPoint: CGPoint, to endPoint: CGPoint, pixelSpacing: PixelSpacing) -> Double {
        let deltaX = Double(endPoint.x - startPoint.x) * pixelSpacing.x
        let deltaY = Double(endPoint.y - startPoint.y) * pixelSpacing.y
        return sqrt(deltaX * deltaX + deltaY * deltaY)
    }
    
    /// Comprehensive distance calculation from view coordinates to real-world distance
    /// Handles coordinate conversion and pixel spacing automatically
    public func calculateDistanceFromViewCoordinates(viewPoint1: CGPoint, viewPoint2: CGPoint, dicomView: UIView, imageWidth: Int, imageHeight: Int, pixelSpacing: PixelSpacing) -> (distance: Double, pixelPoints: (CGPoint, CGPoint)) {
        
        // Convert view points to image pixel coordinates
        let point1InPixel = convertViewToImagePixelPoint(viewPoint1, dicomView: dicomView, imageWidth: imageWidth, imageHeight: imageHeight)
        let point2InPixel = convertViewToImagePixelPoint(viewPoint2, dicomView: dicomView, imageWidth: imageWidth, imageHeight: imageHeight)
        
        // Calculate pixel distance in image coordinates
        let deltaX = point2InPixel.x - point1InPixel.x
        let deltaY = point2InPixel.y - point1InPixel.y
        let pixelDistance = sqrt(deltaX * deltaX + deltaY * deltaY)
        
        // Calculate real distance in mm using pixel spacing
        let realDistanceX = abs(deltaX) * pixelSpacing.x
        let realDistanceY = abs(deltaY) * pixelSpacing.y
        let realDistance = sqrt(realDistanceX * realDistanceX + realDistanceY * realDistanceY)
        
        print("📏 Distance calculated: \(String(format: "%.2f", realDistance))mm (pixel dist: \(String(format: "%.1f", pixelDistance))px)")
        
        return (distance: realDistance, pixelPoints: (point1InPixel, point2InPixel))
    }
    
    // MARK: - Measurement Management
    
    /// Clear all measurement overlays and labels
    /// Handles UI cleanup for measurements across the application
    public func clearAllMeasurements(from overlays: inout [CAShapeLayer], labels: inout [UILabel], currentOverlay: inout CAShapeLayer?) {
        print("🧹 [ROIMeasurementService] Clearing all measurements")
        
        // Remove overlay layers
        overlays.forEach { $0.removeFromSuperlayer() }
        overlays.removeAll()
        
        // Remove measurement labels  
        labels.forEach { $0.removeFromSuperview() }
        labels.removeAll()
        
        // Clear current overlay path
        currentOverlay?.path = nil
        
        print("✅ [ROIMeasurementService] All measurements cleared")
    }
    
    /// Clear completed measurements with ROIMeasurement structure
    /// Compatible with SwiftDetailViewController's completedMeasurements array
    public func clearCompletedMeasurements<T>(_ completedMeasurements: inout [T]) where T: AnyObject {
        print("🧹 [ROIMeasurementService] Clearing completed measurements")
        
        // Remove all completed measurement overlays and labels
        for measurement in completedMeasurements {
            // Use reflection to safely access overlay and labels properties
            let mirror = Mirror(reflecting: measurement)
            
            for child in mirror.children {
                switch child.label {
                case "overlay":
                    if let overlay = child.value as? CAShapeLayer {
                        overlay.removeFromSuperlayer()
                    }
                case "labels":
                    if let labels = child.value as? [UILabel] {
                        labels.forEach { $0.removeFromSuperview() }
                    }
                default:
                    continue
                }
            }
        }
        
        completedMeasurements.removeAll()
        print("✅ [ROIMeasurementService] Completed measurements cleared")
    }
    
    /// Reset measurement state for new measurement session
    public func resetMeasurementState() -> MeasurementResetResult {
        print("🔄 [ROIMeasurementService] Resetting measurement state")
        return MeasurementResetResult(shouldEnableWindowLevel: true, newMode: .none)
    }
    
    /// Convert view coordinates to image pixel coordinates  
    private func convertViewToImagePixelPoint(_ viewPoint: CGPoint, dicomView: UIView, imageWidth: Int, imageHeight: Int) -> CGPoint {
        // Get image and view dimensions
        let imgWidth = CGFloat(imageWidth)
        let imgHeight = CGFloat(imageHeight)
        let viewWidth = dicomView.bounds.width
        let viewHeight = dicomView.bounds.height
        
        // Calculate the aspect ratios
        let imageAspectRatio = imgWidth / imgHeight
        let viewAspectRatio = viewWidth / viewHeight
        
        var scaleFactor: CGFloat
        var offsetX: CGFloat = 0
        var offsetY: CGFloat = 0
        
        if imageAspectRatio > viewAspectRatio {
            // Image is wider than view - letterboxed vertically
            scaleFactor = imgWidth / viewWidth
            let scaledImageHeight = imgHeight / scaleFactor
            offsetY = (viewHeight - scaledImageHeight) / 2
        } else {
            // Image is taller than view - letterboxed horizontally  
            scaleFactor = imgHeight / viewHeight
            let scaledImageWidth = imgWidth / scaleFactor
            offsetX = (viewWidth - scaledImageWidth) / 2
        }
        
        // Convert view coordinates to image coordinates
        let adjustedX = (viewPoint.x - offsetX) * scaleFactor
        let adjustedY = (viewPoint.y - offsetY) * scaleFactor
        
        // Clamp to image bounds
        let clampedX = max(0, min(adjustedX, imgWidth - 1))
        let clampedY = max(0, min(adjustedY, imgHeight - 1))
        
        return CGPoint(x: clampedX, y: clampedY)
    }
    
    public func calculateEllipseArea(points: [CGPoint], pixelSpacing: PixelSpacing) -> Double {
        guard points.count >= 2 else { return 0 }
        
        // For simplicity, treat as ellipse with major and minor axes
        let bounds = points.reduce(CGRect.null) { result, point in
            result.union(CGRect(origin: point, size: CGSize(width: 1, height: 1)))
        }
        
        let majorAxis = Double(bounds.width) * pixelSpacing.x
        let minorAxis = Double(bounds.height) * pixelSpacing.y
        
        // Area of ellipse = π * a * b (where a and b are semi-major and semi-minor axes)
        return Double.pi * (majorAxis / 2.0) * (minorAxis / 2.0)
    }
    
    /// Comprehensive ellipse density calculation from view coordinates
    /// Handles coordinate conversion, pixel analysis, and HU density calculation
    public func calculateEllipseDensityFromViewCoordinates(centerView: CGPoint, edgeView: CGPoint, dicomView: UIView, imageWidth: Int, imageHeight: Int, pixelData: Data?, rescaleSlope: Double, rescaleIntercept: Double) -> (averageHU: Double, pixelCount: Int, centerPixel: CGPoint, radiusPixel: Double)? {
        
        // Convert view points to image pixel coordinates  
        let centerInPixel = convertViewToImagePixelPoint(centerView, dicomView: dicomView, imageWidth: imageWidth, imageHeight: imageHeight)
        let edgeInPixel = convertViewToImagePixelPoint(edgeView, dicomView: dicomView, imageWidth: imageWidth, imageHeight: imageHeight)
        
        // Calculate radius in pixel coordinates
        let radiusInPixel = sqrt(pow(Double(edgeInPixel.x - centerInPixel.x), 2) + pow(Double(edgeInPixel.y - centerInPixel.y), 2))
        
        // Safety check for radius
        guard radiusInPixel > 0 else {
            print("⚠️ [ROI] Ellipse calculation cancelled: zero radius")
            return nil
        }
        
        // Get pixel data
        guard let pixelData = pixelData else {
            print("❌ [ROI] Unable to get pixel data for ellipse measurement")
            return nil
        }
        
        let width = imageWidth
        let height = imageHeight
        
        // Convert Data to UInt16 array for processing
        let pixels16 = pixelData.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: UInt16.self))
        }
        
        // Calculate average HU within circle
        var sumHU = 0.0
        var pixelCount = 0
        
        // Scan pixels within bounding box of circle
        let minX = max(0, Int(centerInPixel.x - radiusInPixel))
        let maxX = min(width - 1, Int(centerInPixel.x + radiusInPixel))
        let minY = max(0, Int(centerInPixel.y - radiusInPixel))
        let maxY = min(height - 1, Int(centerInPixel.y + radiusInPixel))
        
        // Safety check for bounding box
        guard minX <= maxX, minY <= maxY else {
            print("⚠️ [ROI] Ellipse calculation cancelled: invalid bounding box")
            return nil
        }
        
        // Calculate sum of HU values within the ellipse
        let maxPixelIndex = width * height
        for y in minY...maxY {
            for x in minX...maxX {
                let distSq = pow(Double(x) - Double(centerInPixel.x), 2) + pow(Double(y) - Double(centerInPixel.y), 2)
                if distSq <= Double(radiusInPixel * radiusInPixel) {
                    let pixelIndex = y * width + x
                    guard pixelIndex >= 0 && pixelIndex < maxPixelIndex else { continue }
                    let pixelValue = Double(pixels16[pixelIndex])
                    
                    // Apply rescale values to get HU
                    let huValue = (pixelValue * rescaleSlope) + rescaleIntercept
                    sumHU += huValue
                    pixelCount += 1
                }
            }
        }
        
        // Calculate average HU
        let averageHU = pixelCount > 0 ? sumHU / Double(pixelCount) : 0
        
        print("🔵 [ROI] Ellipse density calculated: \(String(format: "%.1f", averageHU)) HU from \(pixelCount) pixels")
        
        return (averageHU: averageHU, pixelCount: pixelCount, centerPixel: centerInPixel, radiusPixel: radiusInPixel)
    }
    
    public func calculateHUDensity(at point: CGPoint, pixelData: Data?, width: Int, height: Int) -> Double? {
        // Extract pixel value at the given point
        guard let pixelData = pixelData else { return nil }
        
        let x = Int(point.x)
        let y = Int(point.y)
        
        guard x >= 0 && x < width && y >= 0 && y < height else { return nil }
        
        // Calculate pixel index
        let pixelIndex = y * width + x
        
        // Get pixel value (assuming 16-bit for now)
        let pixels16 = pixelData.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: UInt16.self))
        }
        
        guard pixelIndex < pixels16.count else { return nil }
        
        let rawValue = Int16(bitPattern: pixels16[pixelIndex])
        // Note: rescale values should be passed from caller if needed
        let hounsfield = Double(rawValue)
        return hounsfield
    }
    
    // MARK: - Coordinate Conversion
    
    public func convertToImagePixelPoint(_ viewPoint: CGPoint, in dicomView: UIView, imageWidth: Int, imageHeight: Int) -> CGPoint {
        // The viewPoint is already in dicomView's coordinate system (post-transformation)
        // because we capture it using gesture.location(in: dicomView)
        
        // Get image and view dimensions
        let imgWidth = CGFloat(imageWidth)
        let imgHeight = CGFloat(imageHeight)
        let viewWidth = dicomView.bounds.width
        let viewHeight = dicomView.bounds.height
        
        // Calculate the aspect ratios
        let imageAspectRatio = imgWidth / imgHeight
        let viewAspectRatio = viewWidth / viewHeight
        
        // Determine the actual display dimensions within the view
        // The image is scaled to fit within the view while maintaining aspect ratio
        var displayWidth: CGFloat
        var displayHeight: CGFloat
        var offsetX: CGFloat = 0
        var offsetY: CGFloat = 0
        
        if imageAspectRatio > viewAspectRatio {
            // Image is wider - fit to width
            displayWidth = viewWidth
            displayHeight = viewWidth / imageAspectRatio
            offsetY = (viewHeight - displayHeight) / 2
        } else {
            // Image is taller - fit to height
            displayHeight = viewHeight
            displayWidth = viewHeight * imageAspectRatio
            offsetX = (viewWidth - displayWidth) / 2
        }
        
        // Adjust the point for the offset
        let adjustedPoint = CGPoint(x: viewPoint.x - offsetX,
                                   y: viewPoint.y - offsetY)
        
        // Check if point is within the actual image bounds
        if adjustedPoint.x < 0 || adjustedPoint.x > displayWidth ||
           adjustedPoint.y < 0 || adjustedPoint.y > displayHeight {
            // Point is outside the image
            return CGPoint(x: max(0, min(imgWidth - 1, adjustedPoint.x * imgWidth / displayWidth)),
                          y: max(0, min(imgHeight - 1, adjustedPoint.y * imgHeight / displayHeight)))
        }
        
        // Convert to pixel coordinates
        return CGPoint(x: adjustedPoint.x * imgWidth / displayWidth,
                      y: adjustedPoint.y * imgHeight / displayHeight)
    }
    
    public func clearAllMeasurements() {
        measurements.removeAll()
        activeMeasurementPoints.removeAll()
        currentMeasurementMode = .none
        print("[ROI] All measurements cleared")
    }
    
    public func clearMeasurement(withId id: UUID) {
        measurements.removeAll { $0.id == id }
        print("[ROI] Measurement \(id) cleared")
    }
    
    public func isValidMeasurement() -> Bool {
        switch currentMeasurementMode {
        case .distance:
            return activeMeasurementPoints.count == 2
        case .ellipse:
            return activeMeasurementPoints.count >= 2
        case .none:
            return false
        }
    }
    
    // MARK: - Configuration
    
    public func updatePixelSpacing(_ pixelSpacing: PixelSpacing) {
        self.currentPixelSpacing = pixelSpacing
    }
    
    // updateDecoder removed - no longer needed with DcmSwift
    
    // MARK: - Private Methods
    
    private func completeDistanceMeasurement() -> MeasurementResult? {
        guard activeMeasurementPoints.count == 2 else { return nil }
        
        let distance = calculateDistance(
            from: activeMeasurementPoints[0],
            to: activeMeasurementPoints[1],
            pixelSpacing: currentPixelSpacing
        )
        
        let displayValue = String(format: "%.2f mm", distance)
        
        let measurement = ROIMeasurementData(
            type: .distance,
            points: activeMeasurementPoints,
            value: displayValue,
            pixelSpacing: currentPixelSpacing
        )
        
        measurements.append(measurement)
        
        // Reset for next measurement
        resetActiveMeasurement()
        
        return MeasurementResult(
            measurement: measurement,
            displayValue: displayValue,
            rawValue: distance
        )
    }
    
    private func completeEllipseMeasurement() -> MeasurementResult? {
        guard activeMeasurementPoints.count >= 2 else { return nil }
        
        let area = calculateEllipseArea(points: activeMeasurementPoints, pixelSpacing: currentPixelSpacing)
        
        // Also calculate average HU if decoder is available
        let displayValue = String(format: "Area: %.2f mm²", area)
        
        let measurement = ROIMeasurementData(
            type: .ellipse,
            points: activeMeasurementPoints,
            value: displayValue,
            pixelSpacing: currentPixelSpacing
        )
        
        measurements.append(measurement)
        
        // Reset for next measurement
        resetActiveMeasurement()
        
        return MeasurementResult(
            measurement: measurement,
            displayValue: displayValue,
            rawValue: area
        )
    }
    
    private func calculateAverageHU(in points: [CGPoint], imageWidth: Int, imageHeight: Int, pixelData: Data?, rescaleSlope: Double, rescaleIntercept: Double) -> Double? {
        guard points.count >= 2 else { return nil }
        
        // Calculate bounding rectangle
        let bounds = points.reduce(CGRect.null) { result, point in
            result.union(CGRect(origin: point, size: CGSize(width: 1, height: 1)))
        }
        
        var totalHU = 0.0
        var validPixels = 0
        
        // Sample pixels within the bounds (simplified approach)
        let stepX = max(1, Int(bounds.width / 10)) // Sample every 10th pixel for performance
        let stepY = max(1, Int(bounds.height / 10))
        
        for x in stride(from: Int(bounds.minX), to: Int(bounds.maxX), by: stepX) {
            for y in stride(from: Int(bounds.minY), to: Int(bounds.maxY), by: stepY) {
                if let hu = calculateHUDensity(at: CGPoint(x: x, y: y), pixelData: pixelData, width: imageWidth, height: imageHeight) {
                    totalHU += hu
                    validPixels += 1
                }
            }
        }
        
        return validPixels > 0 ? totalHU / Double(validPixels) : nil
    }
    
    private func resetActiveMeasurement() {
        activeMeasurementPoints.removeAll()
        currentMeasurementMode = .none
    }
        
    // MARK: - Phase 11E: Measurement Event Handling
    
    /// Handle measurement cleared event
    /// Provides centralized logging and potential future processing for cleared measurements
    public func handleMeasurementsCleared() {
        print("📏 [ROIMeasurementService] All measurements cleared - notifying observers")
        // Future: Could notify observers, update analytics, etc.
    }
    
    /// Handle distance measurement completion
    /// Provides centralized processing for completed distance measurements
    internal func handleDistanceMeasurementCompleted(_ measurement: ROIMeasurement) {
        print("📏 [ROIMeasurementService] Distance measurement completed: \(measurement.value ?? "unknown")")
        
        // Future processing could include:
        // - Analytics tracking
        // - Measurement history storage
        // - Export preparation
        // - Validation checks
    }
    
    /// Handle ellipse measurement completion  
    /// Provides centralized processing for completed ellipse measurements
    internal func handleEllipseMeasurementCompleted(_ measurement: ROIMeasurement) {
        print("📏 [ROIMeasurementService] Ellipse measurement completed: \(measurement.value ?? "unknown")")
        
        // Future processing could include:
        // - Density analysis
        // - Area calculations
        // - HU statistics
        // - Region export
    }
    
    /// Handle ROI tool selection events
    /// Centralized management of ROI tool activation
    internal func handleROIToolSelection(_ toolType: ROIToolType, measurementView: ROIMeasurementToolsProtocol?) {
        print("🎯 [ROIMeasurementService] ROI tool selected: \(toolType)")
        
        switch toolType {
        case .distance:
            measurementView?.activateDistanceMeasurement()
            print("✅ [ROIMeasurementService] Distance measurement tool activated")
        case .ellipse:
            measurementView?.activateEllipseMeasurement()  
            print("✅ [ROIMeasurementService] Ellipse measurement tool activated")
        case .clearAll:
            // Clear all will be handled by calling clearAllMeasurements
            print("🧹 [ROIMeasurementService] Clear all measurements requested")
        }
    }
}

// MARK: - Extensions

extension CGRect {
    static let null = CGRect(x: CGFloat.greatestFiniteMagnitude, 
                            y: CGFloat.greatestFiniteMagnitude, 
                            width: 0, height: 0)
}