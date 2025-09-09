#if canImport(CoreGraphics)
import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Supporting Types

/// Supported measurement modes for ROI tools
public enum ROIMeasurementMode: String, CaseIterable, Sendable {
    case none
    case distance
    case ellipse
}

/// Pixel spacing representation in millimetres
public struct PixelSpacing: Sendable {
    public let x: Double
    public let y: Double
    public static let unknown = PixelSpacing(x: 1, y: 1)
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Stored measurement information
public struct ROIMeasurementData: Sendable {
    public let id: UUID
    public let type: ROIMeasurementMode
    public let points: [CGPoint]
    public let value: String
    public let pixelSpacing: PixelSpacing

    public init(type: ROIMeasurementMode, points: [CGPoint], value: String, pixelSpacing: PixelSpacing) {
        self.id = UUID()
        self.type = type
        self.points = points
        self.value = value
        self.pixelSpacing = pixelSpacing
    }
  }

  /// Result returned when a measurement is completed
public struct MeasurementResult: Sendable {
    public let measurement: ROIMeasurementData
    public let displayValue: String
    public let rawValue: Double
}

// MARK: - Protocol

/// Service abstraction so UI layers can drive ROI measurements
public protocol ROIMeasurementServiceProtocol: Sendable {
    var currentMeasurementMode: ROIMeasurementMode { get set }
    var activeMeasurementPoints: [CGPoint] { get }
    var measurements: [ROIMeasurementData] { get }

    func startDistanceMeasurement(at point: CGPoint)
    func startEllipseMeasurement(at point: CGPoint)
    func addMeasurementPoint(_ point: CGPoint)
    func completeMeasurement() -> MeasurementResult?
    func calculateDistance(from: CGPoint, to: CGPoint, pixelSpacing: PixelSpacing) -> Double
    func calculateEllipseArea(points: [CGPoint], pixelSpacing: PixelSpacing) -> Double
    func clearAllMeasurements()
    func clearMeasurement(withId id: UUID)
    func isValidMeasurement() -> Bool
    func updatePixelSpacing(_ pixelSpacing: PixelSpacing)

    #if canImport(UIKit)
    func convertToImagePixelPoint(_ viewPoint: CGPoint, in dicomView: UIView, imageWidth: Int, imageHeight: Int) -> CGPoint
    func calculateDistanceFromViewCoordinates(viewPoint1: CGPoint, viewPoint2: CGPoint, dicomView: UIView, imageWidth: Int, imageHeight: Int, pixelSpacing: PixelSpacing) -> (distance: Double, pixelPoints: (CGPoint, CGPoint))
    #endif
}

// MARK: - Service Implementation

public final class ROIMeasurementService: ROIMeasurementServiceProtocol {
    public var currentMeasurementMode: ROIMeasurementMode = .none
    public private(set) var activeMeasurementPoints: [CGPoint] = []
    public private(set) var measurements: [ROIMeasurementData] = []
    private var currentPixelSpacing: PixelSpacing = .unknown

    public init() {}

    // MARK: - Measurement Lifecycle

    public func startDistanceMeasurement(at point: CGPoint) {
        currentMeasurementMode = .distance
        activeMeasurementPoints = [point]
    }

    public func startEllipseMeasurement(at point: CGPoint) {
        currentMeasurementMode = .ellipse
        activeMeasurementPoints = [point]
    }

    public func addMeasurementPoint(_ point: CGPoint) {
        switch currentMeasurementMode {
        case .distance:
            if activeMeasurementPoints.count < 2 {
                activeMeasurementPoints.append(point)
            } else {
                activeMeasurementPoints[1] = point
            }
        case .ellipse:
            activeMeasurementPoints.append(point)
        case .none:
            break
        }
    }

    public func completeMeasurement() -> MeasurementResult? {
        guard isValidMeasurement() else { return nil }

        switch currentMeasurementMode {
        case .distance:
            let distance = calculateDistance(from: activeMeasurementPoints[0], to: activeMeasurementPoints[1], pixelSpacing: currentPixelSpacing)
            let display = String(format: "%.2f mm", distance)
            let data = ROIMeasurementData(type: .distance, points: activeMeasurementPoints, value: display, pixelSpacing: currentPixelSpacing)
            measurements.append(data)
            activeMeasurementPoints.removeAll()
            currentMeasurementMode = .none
            return MeasurementResult(measurement: data, displayValue: display, rawValue: distance)
        case .ellipse:
            let area = calculateEllipseArea(points: activeMeasurementPoints, pixelSpacing: currentPixelSpacing)
            let display = String(format: "Area: %.2f mm²", area)
            let data = ROIMeasurementData(type: .ellipse, points: activeMeasurementPoints, value: display, pixelSpacing: currentPixelSpacing)
            measurements.append(data)
            activeMeasurementPoints.removeAll()
            currentMeasurementMode = .none
            return MeasurementResult(measurement: data, displayValue: display, rawValue: area)
        case .none:
            return nil
        }
    }

    // MARK: - Calculations

    public func calculateDistance(from startPoint: CGPoint, to endPoint: CGPoint, pixelSpacing: PixelSpacing) -> Double {
        let dx = Double(endPoint.x - startPoint.x) * pixelSpacing.x
        let dy = Double(endPoint.y - startPoint.y) * pixelSpacing.y
        return sqrt(dx * dx + dy * dy)
    }

    public func calculateEllipseArea(points: [CGPoint], pixelSpacing: PixelSpacing) -> Double {
        guard points.count >= 2 else { return 0 }
        let bounds = points.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: CGSize(width: 1, height: 1))) }
        let major = Double(bounds.width) * pixelSpacing.x
        let minor = Double(bounds.height) * pixelSpacing.y
        return Double.pi * (major / 2.0) * (minor / 2.0)
    }

    // MARK: - Management

    public func clearAllMeasurements() {
        measurements.removeAll()
        activeMeasurementPoints.removeAll()
        currentMeasurementMode = .none
    }

    public func clearMeasurement(withId id: UUID) {
        measurements.removeAll { $0.id == id }
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

    public func updatePixelSpacing(_ pixelSpacing: PixelSpacing) {
        currentPixelSpacing = pixelSpacing
    }

    // MARK: - UIKit Helpers
    #if canImport(UIKit)
    public func convertToImagePixelPoint(_ viewPoint: CGPoint, in dicomView: UIView, imageWidth: Int, imageHeight: Int) -> CGPoint {
        let imgWidth = CGFloat(imageWidth)
        let imgHeight = CGFloat(imageHeight)
        let viewWidth = dicomView.bounds.width
        let viewHeight = dicomView.bounds.height
        let imageAspect = imgWidth / imgHeight
        let viewAspect = viewWidth / viewHeight

        var displayWidth: CGFloat
        var displayHeight: CGFloat
        var offsetX: CGFloat = 0
        var offsetY: CGFloat = 0

        if imageAspect > viewAspect {
            displayWidth = viewWidth
            displayHeight = viewWidth / imageAspect
            offsetY = (viewHeight - displayHeight) / 2
        } else {
            displayHeight = viewHeight
            displayWidth = viewHeight * imageAspect
            offsetX = (viewWidth - displayWidth) / 2
        }

        let adjusted = CGPoint(x: viewPoint.x - offsetX, y: viewPoint.y - offsetY)
        return CGPoint(x: adjusted.x * imgWidth / displayWidth, y: adjusted.y * imgHeight / displayHeight)
    }

    public func calculateDistanceFromViewCoordinates(viewPoint1: CGPoint, viewPoint2: CGPoint, dicomView: UIView, imageWidth: Int, imageHeight: Int, pixelSpacing: PixelSpacing) -> (distance: Double, pixelPoints: (CGPoint, CGPoint)) {
        let p1 = convertToImagePixelPoint(viewPoint1, in: dicomView, imageWidth: imageWidth, imageHeight: imageHeight)
        let p2 = convertToImagePixelPoint(viewPoint2, in: dicomView, imageWidth: imageWidth, imageHeight: imageHeight)
        let distance = calculateDistance(from: p1, to: p2, pixelSpacing: pixelSpacing)
        return (distance, (p1, p2))
    }
    #endif
}

#endif
