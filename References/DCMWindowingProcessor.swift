//
//  DCMWindowingProcessor.swift
//  DICOMViewer
//
//  This
//  type encapsulates medical imaging window/level calculations,
//  basic image enhancement techniques and quality metrics.  All
//  methods are static and operate on Swift collection types
//  rather than raw pointers.  The use of generics and value
//  semantics improves safety and performance compared to the
//  original implementation.  Accelerate is leveraged where
//  appropriate for efficient vectorised operations.
//

import Foundation
import Accelerate

// MARK: - Medical Preset Enumeration

/// Enumeration of common preset window/level settings used in
/// medical imaging.  The underlying raw values mirror those used
/// in the Objective‑C NS_ENUM.  Each case describes a typical
/// anatomy or modality and can be mapped to a pair of centre and
/// width values via ``getPresetValues(preset:)``.
enum MedicalPreset: Int {
    case lung       = 0
    case bone       = 1
    case softTissue = 2
    case brain      = 3
    case liver      = 4
    case custom     = 5
}

// MARK: - Window/Level Operations Struct

/// A collection of static methods providing window/level
/// transformations, image enhancement and statistical analysis for
/// 16‑bit medical images.  For simplicity the API accepts Swift
/// arrays rather than pointers.  When returning modified image
/// data the methods produce ``Data`` objects containing raw
/// 8‑bit pixel bytes.  See each method for details.
public struct DCMWindowingProcessor {
    
    // MARK: - Core Window/Level Operations

    /// Applies a linear window/level transformation to a 16‑bit
    /// grayscale pixel buffer.  The resulting pixels are scaled to
    /// the 0–255 range and returned as ``Data``.  This function
    /// mirrors the Objective‑C `applyWindowLevel:length:center:width:`
    /// implementation but uses Swift arrays and vDSP for improved
    /// clarity.  If the input is empty or the width is non‑positive
    /// the function returns nil.
    ///
    /// - Parameters:
    ///   - pixels16: An array of unsigned 16‑bit pixel intensities.
    ///   - center: The centre of the window.
    ///   - width: The width of the window.
    /// - Returns: A ``Data`` object containing 8‑bit pixel values or
    ///   `nil` if the input is invalid.
    static func applyWindowLevel(pixels16: [UInt16],
                                 center: Double,
                                 width: Double) -> Data? {
        guard !pixels16.isEmpty, width > 0 else { return nil }
        let length = vDSP_Length(pixels16.count)
        // Calculate min and max levels
        let minLevel = center - width / 2.0
        let maxLevel = center + width / 2.0
        let range = maxLevel - minLevel
        let rangeInv: Double = range > 0 ? 255.0 / range : 1.0
        // Convert UInt16 to Double for processing
        var doubles = pixels16.map { Double($0) }
        // Subtract min level
        var minLevelScalar = minLevel
        var tempDoubles = [Double](repeating: 0, count: pixels16.count)
        vDSP_vsaddD(&doubles, 1, &minLevelScalar, &tempDoubles, 1, length)
        // Multiply by scaling factor
        var scale = rangeInv
        vDSP_vsmulD(&tempDoubles, 1, &scale, &doubles, 1, length)
        // Allocate output buffer
        var bytes = [UInt8](repeating: 0, count: pixels16.count)
        for i in 0..<pixels16.count {
            var value = doubles[i]
            // Clamp between 0 and 255
            value = max(0.0, min(255.0, value))
            bytes[i] = UInt8(value)
        }
        return Data(bytes)
    }

    /// Calculates an optimal window centre and width based on the
    /// 1st and 99th percentiles of the pixel value distribution.
    /// This mirrors the Objective‑C
    /// `calculateOptimalWindowLevel:length:center:width:` function.
    /// If the input array is empty the mean and full range are
    /// returned.  The histogram is computed using 256 bins.
    ///
    /// - Parameter pixels16: Array of 16‑bit pixel values.
    /// - Returns: A tuple `(center, width)` representing the
    ///   calculated window centre and width.
    static func calculateOptimalWindowLevel(pixels16: [UInt16]) -> (center: Double, width: Double) {
        guard !pixels16.isEmpty else { return (0.0, 0.0) }
        // Compute histogram and basic stats
        var minValue: Double = 0
        var maxValue: Double = 0
        var meanValue: Double = 0
        let histogram = calculateHistogram(pixels16: pixels16,
                                           minValue: &minValue,
                                           maxValue: &maxValue,
                                           meanValue: &meanValue)
        guard !histogram.isEmpty else {
            return (center: meanValue, width: maxValue - minValue)
        }
        // Determine thresholds for 1st and 99th percentiles
        let totalPixels = pixels16.count
        let p1Threshold = Int(Double(totalPixels) * 0.01)
        let p99Threshold = Int(Double(totalPixels) * 0.99)
        var cumulativeCount = 0
        var p1Value = minValue
        var p99Value = maxValue
        let binWidth = (maxValue - minValue) / Double(histogram.count)
        for (i, count) in histogram.enumerated() {
            cumulativeCount += count
            let binValue = minValue + (Double(i) + 0.5) * binWidth
            if cumulativeCount >= p1Threshold && p1Value == minValue {
                p1Value = binValue
            }
            if cumulativeCount >= p99Threshold {
                p99Value = binValue
                break
            }
        }
        let center = (p1Value + p99Value) / 2.0
        let width = p99Value - p1Value
        return (center, width)
    }

    // MARK: - Image Enhancement Methods

    /// Applies a simplified Contrast Limited Adaptive Histogram
    /// Equalization (CLAHE) to an 8‑bit grayscale image.  The
    /// implementation here performs a global contrast stretch as a
    /// placeholder; a production version should implement true
    /// adaptive equalisation.  Input and output are raw pixel data
    /// represented as ``Data``.  If the input is invalid the
    /// function returns nil.
    ///
    /// - Parameters:
    ///   - imageData: Raw 8‑bit pixel data (length = width × height).
    ///   - width: Image width in pixels.
    ///   - height: Image height in pixels.
    ///   - clipLimit: Parameter for future CLAHE implementation
    ///     (currently unused).
    /// - Returns: New image data with stretched contrast or nil.
    static func applyCLAHE(imageData: Data,
                           width: Int,
                           height: Int,
                           clipLimit: Double) -> Data? {
        // Ensure input is valid
        guard width > 0, height > 0, imageData.count == width * height else { return nil }
        // Copy into mutable array
        var pixels = [UInt8](imageData)
        let pixelCount = pixels.count
        // Compute histogram
        var histogram = [Int](repeating: 0, count: 256)
        for p in pixels { histogram[Int(p)] += 1 }
        // Clip histogram: clipLimit is a percentage (0–1) of the average count
        let avgCount = Double(pixelCount) / 256.0
        let threshold = max(1.0, clipLimit * avgCount)
        var excess: Double = 0.0
        for i in 0..<256 {
            if Double(histogram[i]) > threshold {
                excess += Double(histogram[i]) - threshold
                histogram[i] = Int(threshold)
            }
        }
        // Redistribute excess uniformly
        let increment = Int(excess / 256.0)
        for i in 0..<256 { histogram[i] += increment }
        // Compute cumulative distribution function (CDF)
        var cdf = [Double](repeating: 0.0, count: 256)
        var cumulative: Double = 0.0
        for i in 0..<256 {
            cumulative += Double(histogram[i])
            cdf[i] = cumulative
        }
        // Normalize CDF to [0,255]
        let cdfMin = cdf.first { $0 > 0 } ?? 0.0
        let denom = cdf.last! - cdfMin
        // Map each pixel using the CDF
        for i in 0..<pixelCount {
            let value = Int(pixels[i])
            let cdfValue = cdf[value]
            let normalized = (cdfValue - cdfMin) / (denom > 0 ? denom : 1.0)
            pixels[i] = UInt8(max(0.0, min(255.0, normalized * 255.0)))
        }
        return Data(pixels)
    }

    /// Applies a simple 3×3 Gaussian blur to reduce noise in an
    /// 8‑bit grayscale image.  The strength parameter controls the
    /// blending between the original and blurred image: 0 = no
    /// filtering, 1 = fully blurred.  Values below 0.1 have no
    /// effect.  A more sophisticated implementation would use a
    /// separable kernel or a larger convolution matrix.
    ///
    /// - Parameters:
    ///   - imageData: Raw 8‑bit pixel data (length = width × height).
    ///   - width: Image width in pixels.
    ///   - height: Image height in pixels.
    ///   - strength: Blend factor between 0.0 and 1.0.
    /// - Returns: New image data with reduced noise or nil.
    static func applyNoiseReduction(imageData: Data,
                                    width: Int,
                                    height: Int,
                                    strength: Double) -> Data? {
        guard width > 0, height > 0, imageData.count == width * height else { return nil }
        let pixels = [UInt8](imageData)
        let strengthClamped = max(0.0, min(1.0, strength))
        guard strengthClamped > 0.1 else { return Data(pixels) }
        var tempPixels = pixels
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let idx = y * width + x
                // Approximate 3×3 Gaussian kernel
                var sum = Double(pixels[idx]) * 4.0
                sum += Double(pixels[idx - width - 1]) * 1.0
                sum += Double(pixels[idx - width]) * 2.0
                sum += Double(pixels[idx - width + 1]) * 1.0
                sum += Double(pixels[idx - 1]) * 2.0
                sum += Double(pixels[idx + 1]) * 2.0
                sum += Double(pixels[idx + width - 1]) * 1.0
                sum += Double(pixels[idx + width]) * 2.0
                sum += Double(pixels[idx + width + 1]) * 1.0
                sum /= 16.0
                // Blend with original
                let original = Double(pixels[idx])
                let blurred = sum
                tempPixels[idx] = UInt8(original * (1.0 - strengthClamped) + blurred * strengthClamped)
            }
        }
        return Data(tempPixels)
    }

    // MARK: - Preset Management

    /// Returns preset window/level values corresponding to a given
    /// medical preset.  If the preset is ``custom`` the full
    /// dynamic range is returned.  These values correspond to
    /// standard Hounsfield Unit ranges used in radiology.
    ///
    /// - Parameter preset: The anatomical preset.
    /// - Returns: A tuple `(center, width)` with default values.
    static func getPresetValues(preset: MedicalPreset) -> (center: Double, width: Double) {
        switch preset {
        case .lung:
            return (-600.0, 1200.0)
        case .bone:
            return (400.0, 1800.0)
        case .softTissue:
            return (50.0, 350.0)
        case .brain:
            return (40.0, 80.0)
        case .liver:
            return (120.0, 200.0)
        case .custom:
            fallthrough
        default:
            return (0.0, 4096.0)
        }
    }

    // MARK: - Statistical Analysis

    /// Calculates a histogram of the input 16‑bit pixel values using
    /// 256 bins spanning the range from the minimum to maximum
    /// intensity.  The function also computes the minimum,
    /// maximum and mean values.  The histogram counts are returned
    /// as an array of ``Int`` rather than ``NSNumber`` to avoid
    /// boxing overhead.  This corresponds to the Objective‑C
    /// `calculateHistogram:length:minValue:maxValue:meanValue:`.
    ///
    /// - Parameters:
    ///   - pixels16: An array of unsigned 16‑bit pixel values.
    ///   - minValue: Output parameter receiving the minimum value.
    ///   - maxValue: Output parameter receiving the maximum value.
    ///   - meanValue: Output parameter receiving the mean value.
    /// - Returns: A histogram array with 256 bins representing the
    ///   frequency of pixels within each intensity range.
    static func calculateHistogram(pixels16: [UInt16],
                                   minValue: inout Double,
                                   maxValue: inout Double,
                                   meanValue: inout Double) -> [Int] {
        guard !pixels16.isEmpty else { return [] }
        var minVal: UInt16 = UInt16.max
        var maxVal: UInt16 = 0
        var sum: Double = 0
        for v in pixels16 {
            if v < minVal { minVal = v }
            if v > maxVal { maxVal = v }
            sum += Double(v)
        }
        minValue = Double(minVal)
        maxValue = Double(maxVal)
        meanValue = sum / Double(pixels16.count)
        // Histogram with 256 bins
        let numBins = 256
        var histogram = [Int](repeating: 0, count: numBins)
        let range = Double(maxVal) - Double(minVal)
        guard range > 0 else { return histogram }
        for v in pixels16 {
            let normalized = (Double(v) - Double(minVal)) / range
            var bin = Int(normalized * Double(numBins - 1))
            if bin < 0 { bin = 0 }
            if bin >= numBins { bin = numBins - 1 }
            histogram[bin] += 1
        }
        return histogram
    }

    /// Computes a set of quality metrics for the given 16‑bit pixel
    /// data.  The metrics include mean, standard deviation,
    /// minimum, maximum, Michelson contrast, signal‑to‑noise ratio
    /// and dynamic range.  Results are returned in a dictionary
    /// keyed by descriptive strings.  This corresponds to the
    /// Objective‑C `calculateQualityMetrics:length:`.
    ///
    /// - Parameter pixels16: An array of unsigned 16‑bit pixel values.
    /// - Returns: A dictionary containing quality metrics, or an
    ///   empty dictionary if the input is empty.
    static func calculateQualityMetrics(pixels16: [UInt16]) -> [String: Double] {
        guard !pixels16.isEmpty else { return [:] }
        // Obtain min, max and mean via histogram (histogram itself
        // is discarded here)
        var minValue: Double = 0
        var maxValue: Double = 0
        var meanValue: Double = 0
        _ = calculateHistogram(pixels16: pixels16,
                               minValue: &minValue,
                               maxValue: &maxValue,
                               meanValue: &meanValue)
        // Compute standard deviation
        var variance: Double = 0
        for v in pixels16 {
            let diff = Double(v) - meanValue
            variance += diff * diff
        }
        variance /= Double(pixels16.count)
        let stdDev = sqrt(variance)
        // Michelson contrast
        let contrast = (maxValue - minValue) / (maxValue + minValue + Double.ulpOfOne)
        // Simplified signal‑to‑noise ratio (mean / stdDev)
        let snr = meanValue / (stdDev + Double.ulpOfOne)
        // Dynamic range in decibels
        let dynamicRange = 20.0 * log10(maxValue / (minValue + 1.0))
        return [
            "mean": meanValue,
            "std_deviation": stdDev,
            "min_value": minValue,
            "max_value": maxValue,
            "contrast": contrast,
            "snr": snr,
            "dynamic_range": dynamicRange
        ]
    }

    // MARK: - Utility Methods

    /// Converts a value in Hounsfield Units (HU) to a raw pixel
    /// value given the DICOM rescale slope and intercept.  The
    /// relationship is HU = slope × pixel + intercept.  If
    /// ``rescaleSlope`` is zero the function returns zero to avoid
    /// division by zero.
    ///
    /// - Parameters:
    ///   - hu: Hounsfield unit value.
    ///   - rescaleSlope: DICOM rescale slope.
    ///   - rescaleIntercept: DICOM rescale intercept.
    /// - Returns: The corresponding pixel value.
    static func huToPixelValue(hu: Double,
                               rescaleSlope: Double,
                               rescaleIntercept: Double) -> Double {
        guard rescaleSlope != 0 else { return 0 }
        return (hu - rescaleIntercept) / rescaleSlope
    }

    /// Converts a raw pixel value to Hounsfield Units (HU) given
    /// the DICOM rescale slope and intercept.  The relationship is
    /// HU = slope × pixel + intercept.
    ///
    /// - Parameters:
    ///   - pixelValue: Raw pixel value.
    ///   - rescaleSlope: DICOM rescale slope.
    ///   - rescaleIntercept: DICOM rescale intercept.
    /// - Returns: The corresponding Hounsfield unit value.
    static func pixelValueToHU(pixelValue: Double,
                               rescaleSlope: Double,
                               rescaleIntercept: Double) -> Double {
        return rescaleSlope * pixelValue + rescaleIntercept
    }
}

// MARK: - DCMWindowingProcessor Batch Processing Extensions

extension DCMWindowingProcessor {
    
    /// Apply window/level to multiple images efficiently
    static func batchApplyWindowLevel(
        imagePixels: [[UInt16]],
        centers: [Double],
        widths: [Double]
    ) -> [Data?] {
        guard imagePixels.count == centers.count && centers.count == widths.count else {
            return []
        }
        
        return zip(zip(imagePixels, centers), widths).map { imageCenterWidth in
            let ((pixels, center), width) = imageCenterWidth
            return applyWindowLevel(pixels16: pixels, center: center, width: width)
        }
    }
    
    /// Calculate optimal window/level for a batch of images
    static func batchCalculateOptimalWindowLevel(imagePixels: [[UInt16]]) -> [(center: Double, width: Double)] {
        return imagePixels.map { pixels in
            calculateOptimalWindowLevel(pixels16: pixels)
        }
    }
}

// MARK: - DCMWindowingProcessor Preset Extensions

extension DCMWindowingProcessor {
    
    /// Get all available medical presets
    static var allPresets: [MedicalPreset] {
        return [.lung, .bone, .softTissue, .brain, .liver, .custom]
    }
    
    /// Get preset values by name
    static func getPresetValues(named presetName: String) -> (center: Double, width: Double)? {
        switch presetName.lowercased() {
        case "lung": return getPresetValues(preset: .lung)
        case "bone": return getPresetValues(preset: .bone)
        case "soft tissue", "softtissue": return getPresetValues(preset: .softTissue)
        case "brain": return getPresetValues(preset: .brain)
        case "liver": return getPresetValues(preset: .liver)
        default: return nil
        }
    }
    
    /// Get preset name from values (approximate match)
    static func getPresetName(center: Double, width: Double, tolerance: Double = 50.0) -> String? {
        for preset in allPresets {
            let values = getPresetValues(preset: preset)
            if abs(values.center - center) <= tolerance && abs(values.width - width) <= tolerance {
                switch preset {
                case .lung: return "Lung"
                case .bone: return "Bone"
                case .softTissue: return "Soft Tissue"
                case .brain: return "Brain"
                case .liver: return "Liver"
                case .custom: return "Custom"
                }
            }
        }
        return nil
    }
}

// MARK: - DCMWindowingProcessor Performance Extensions

extension DCMWindowingProcessor {
    
    /// Performance-optimized window/level for large datasets
    static func optimizedApplyWindowLevel(
        pixels16: [UInt16],
        center: Double,
        width: Double,
        useParallel: Bool = true
    ) -> Data? {
        guard !pixels16.isEmpty, width > 0 else { return nil }
        
        let length = vDSP_Length(pixels16.count)
        let minLevel = center - width / 2.0
        let maxLevel = center + width / 2.0
        let range = maxLevel - minLevel
        let rangeInv: Double = range > 0 ? 255.0 / range : 1.0
        
        var bytes = [UInt8](repeating: 0, count: pixels16.count)
        
        if useParallel && pixels16.count > 10000 {
            // Use parallel processing for large datasets
            DispatchQueue.concurrentPerform(iterations: 4) { chunk in
                let start = chunk * pixels16.count / 4
                let end = (chunk == 3) ? pixels16.count : (chunk + 1) * pixels16.count / 4
                
                for i in start..<end {
                    let value = (Double(pixels16[i]) - minLevel) * rangeInv
                    bytes[i] = UInt8(max(0.0, min(255.0, value)))
                }
            }
        } else {
            // Sequential processing for smaller datasets
            for i in 0..<pixels16.count {
                let value = (Double(pixels16[i]) - minLevel) * rangeInv
                bytes[i] = UInt8(max(0.0, min(255.0, value)))
            }
        }
        
        return Data(bytes)
    }
}