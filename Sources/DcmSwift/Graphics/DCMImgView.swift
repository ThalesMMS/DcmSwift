#if canImport(UIKit)
import UIKit
import CoreGraphics
import Foundation

/// Visão leve para exibir buffers de pixels DICOM (grayscale).
/// - Foca em redesenhos eficientes (cache pós-window/level) e reuso de CGContext.
/// - Suporta entrada 8-bit e 16-bit. Para 16-bit, usa LUT (externa ou derivada de window).
@MainActor
public final class DCMImgView: UIView {

    // MARK: - Estado de Pixels
    private var pix8: [UInt8]? = nil
    private var pix16: [UInt16]? = nil
    private var imgWidth: Int = 0
    private var imgHeight: Int = 0

    /// Número de amostras por pixel. Atualmente esperado = 1 (grayscale).
    public var samplesPerPixel: Int = 1

    // MARK: - Window/Level
    public var winCenter: Int = 0 { didSet { updateWindowLevel() } }
    public var winWidth: Int = 0  { didSet { updateWindowLevel() } }
    private var winMin: Int = 0
    private var winMax: Int = 0
    private var lastWinMin: Int = Int.min
    private var lastWinMax: Int = Int.min

    // MARK: - LUT para 16-bit→8-bit
    /// LUT externa opcional. Se presente, é usada em preferência à derivação por window.
    private var lut16: [UInt8]? = nil

    // MARK: - Cache de imagem 8-bit pós-window
    private var cachedImageData: [UInt8]? = nil
    private var cachedImageValid: Bool = false

    // MARK: - Contexto/CoreGraphics
    private var colorspace: CGColorSpace?
    private var bitmapContext: CGContext?
    private var bitmapImage: CGImage?

    private var lastContextWidth: Int = 0
    private var lastContextHeight: Int = 0
    private var lastSamplesPerPixel: Int = 0

    // MARK: - API Pública

    /// Define pixels 8-bit (grayscale) e aplica window.
    public func setPixels8(_ pixels: [UInt8], width: Int, height: Int,
                           windowWidth: Int, windowCenter: Int) {
        pix8 = pixels
        pix16 = nil
        imgWidth = width
        imgHeight = height
        samplesPerPixel = 1
        cachedImageValid = false
        setWindow(center: windowCenter, width: windowWidth)
    }

    /// Define pixels 16-bit (grayscale) e aplica window (ou LUT externa, se definida).
    public func setPixels16(_ pixels: [UInt16], width: Int, height: Int,
                            windowWidth: Int, windowCenter: Int) {
        pix16 = pixels
        pix8 = nil
        imgWidth = width
        imgHeight = height
        samplesPerPixel = 1
        cachedImageValid = false
        setWindow(center: windowCenter, width: windowWidth)
    }

    /// Ajusta window/level explicitamente.
    public func setWindow(center: Int, width: Int) {
        winCenter = center
        winWidth  = width
    }

    /// Define uma LUT 16→8 opcional (tamanho esperado ≥ 65536).
    public func setLUT16(_ lut: [UInt8]?) {
        lut16 = lut
        cachedImageValid = false
        recomputeImage()
        setNeedsDisplay()
    }

    // MARK: - Desenho

    public override func draw(_ rect: CGRect) {
        guard let image = bitmapImage,
              let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.saveGState()
        ctx.interpolationQuality = .none
        ctx.draw(image, in: bounds)
        ctx.restoreGState()
    }

    // MARK: - Window/Level → trigger

    private func updateWindowLevel() {
        let newMin = winCenter - winWidth / 2
        let newMax = winCenter + winWidth / 2

        // Se nada mudou e cache válido, apenas redesenha.
        if newMin == lastWinMin && newMax == lastWinMax && cachedImageValid {
            setNeedsDisplay()
            return
        }

        winMin = newMin
        winMax = newMax
        lastWinMin = newMin
        lastWinMax = newMax

        // Ao mudar window, invalida cache e LUT derivada.
        if lut16 == nil {
            // LUT derivada será (re)gerada em recomputeImage() quando necessário.
        }
        cachedImageValid = false
        recomputeImage()
        setNeedsDisplay()
    }

    // MARK: - Construção de imagem (Core)

    private func recomputeImage() {
        guard imgWidth > 0, imgHeight > 0 else { return }

        // Assegurar reuso de contexto se dimensões/SPP iguais.
        if !shouldReuseContext(width: imgWidth, height: imgHeight, samples: samplesPerPixel) {
            resetImage()
            colorspace = (samplesPerPixel == 1) ? CGColorSpaceCreateDeviceGray()
                                                : CGColorSpaceCreateDeviceRGB()
            lastContextWidth = imgWidth
            lastContextHeight = imgHeight
            lastSamplesPerPixel = samplesPerPixel
        }

        // Alocar/reciclar buffer 8-bit (um canal).
        let pixelCount = imgWidth * imgHeight
        if cachedImageData == nil || cachedImageData!.count != pixelCount * samplesPerPixel {
            cachedImageData = Array(repeating: 0, count: pixelCount * samplesPerPixel)
        }

        // Caminhos: 8-bit direto OU 16-bit com LUT (externa ou derivada de window)
        if let src8 = pix8 {
            applyWindowTo8(src8, into: &cachedImageData!)
        } else if let src16 = pix16 {
            let lut = lut16 ?? buildDerivedLUT16(winMin: winMin, winMax: winMax)
            applyLUTTo16(src16, lut: lut, into: &cachedImageData!)
        } else {
            // Nada para fazer
            return
        }

        cachedImageValid = true

        // Construir CGImage a partir do buffer 8-bit.
        guard let cs = colorspace else { return }
        cachedImageData!.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            // Não fixamos permanentemente 'data' no contexto para evitar reter memória desnecessária:
            // criamos o contexto, fazemos makeImage(), e descartamos o data pointer.
            if let ctx = CGContext(data: base,
                                   width: imgWidth,
                                   height: imgHeight,
                                   bitsPerComponent: 8,
                                   bytesPerRow: imgWidth * samplesPerPixel,
                                   space: cs,
                                   bitmapInfo: samplesPerPixel == 1
                                       ? CGImageAlphaInfo.none.rawValue
                                       : CGImageAlphaInfo.noneSkipLast.rawValue) {
                bitmapContext = ctx
                bitmapImage = ctx.makeImage()
            } else {
                bitmapContext = nil
                bitmapImage = nil
            }
        }
    }

    // MARK: - 8-bit window/level

    private func applyWindowTo8(_ src: [UInt8], into dst: inout [UInt8]) {
        let n = imgWidth * imgHeight
        let denom = max(winMax - winMin, 1)
        // Desenrolar leve para throughput
        var i = 0
        let end = n & ~3
        while i < end {
            let v0 = Int(src[i]);     let c0 = min(max(v0 - winMin, 0), denom)
            let v1 = Int(src[i+1]);   let c1 = min(max(v1 - winMin, 0), denom)
            let v2 = Int(src[i+2]);   let c2 = min(max(v2 - winMin, 0), denom)
            let v3 = Int(src[i+3]);   let c3 = min(max(v3 - winMin, 0), denom)
            dst[i]   = UInt8(c0 * 255 / denom)
            dst[i+1] = UInt8(c1 * 255 / denom)
            dst[i+2] = UInt8(c2 * 255 / denom)
            dst[i+3] = UInt8(c3 * 255 / denom)
            i += 4
        }
        while i < n {
            let v = Int(src[i])
            let clamped = min(max(v - winMin, 0), denom)
            dst[i] = UInt8(clamped * 255 / denom)
            i += 1
        }
    }

    // MARK: - 16-bit via LUT

    /// Constrói LUT derivada de window/level (MONOCHROME2).
    private func buildDerivedLUT16(winMin: Int, winMax: Int) -> [UInt8] {
        // Tamanho mínimo 65536; se houver mais que 16 bits efetivos, clamp em 65536.
        let size = 65536
        var lut = [UInt8](repeating: 0, count: size)
        let denom = max(winMax - winMin, 1)
        // Gera mapeamento linear clampado.
        for v in 0..<size {
            let c = min(max(v - winMin, 0), denom)
            lut[v] = UInt8(c * 255 / denom)
        }
        return lut
    }

    private func applyLUTTo16(_ src: [UInt16], lut: [UInt8], into dst: inout [UInt8]) {
        let numPixels = imgWidth * imgHeight
        guard src.count >= numPixels else {
            print("[DCMImgView] Error: pixel array too small. Expected \(numPixels), got \(src.count)")
            return
        }

        // Tenta GPU (stub retorna false por ora)
        let usedGPU = dst.withUnsafeMutableBufferPointer { outBuf in
            src.withUnsafeBufferPointer { inBuf in
                processPixelsGPU(inputPixels: inBuf.baseAddress!,
                                 outputPixels: outBuf.baseAddress!,
                                 pixelCount: numPixels,
                                 winMin: winMin,
                                 winMax: winMax)
            }
        }
        if usedGPU { return }

        // CPU paralela para imagens grandes
        if numPixels > 2_000_000 {
            let threads = max(1, ProcessInfo.processInfo.activeProcessorCount)
            let chunkSize = (numPixels + threads - 1) / threads
            src.withUnsafeBufferPointer { inBuf in
                lut.withUnsafeBufferPointer { lutBuf in
                    dst.withUnsafeMutableBufferPointer { outBuf in
                        let inBase = inBuf.baseAddress!
                        let lutBase = lutBuf.baseAddress!
                        let outBase = outBuf.baseAddress!
                        DispatchQueue.concurrentPerform(iterations: threads) { chunk in
                            let start = chunk * chunkSize
                            if start >= numPixels { return }
                            let end = min(start + chunkSize, numPixels)
                            var i = start
                            let fastEnd = end & ~3
                            while i < fastEnd {
                                outBase[i]   = lutBase[Int(inBase[i])]
                                outBase[i+1] = lutBase[Int(inBase[i+1])]
                                outBase[i+2] = lutBase[Int(inBase[i+2])]
                                outBase[i+3] = lutBase[Int(inBase[i+3])]
                                i += 4
                            }
                            while i < end {
                                outBase[i] = lutBase[Int(inBase[i])]
                                i += 1
                            }
                        }
                    }
                }
            }
        } else {
            // Caminho sequencial (pequenas)
            src.withUnsafeBufferPointer { inBuf in
                lut.withUnsafeBufferPointer { lutBuf in
                    dst.withUnsafeMutableBufferPointer { outBuf in
                        var i = 0
                        let end = numPixels & ~3
                        while i < end {
                            outBuf[i]   = lutBuf[Int(inBuf[i])]
                            outBuf[i+1] = lutBuf[Int(inBuf[i+1])]
                            outBuf[i+2] = lutBuf[Int(inBuf[i+2])]
                            outBuf[i+3] = lutBuf[Int(inBuf[i+3])]
                            i += 4
                        }
                        while i < numPixels {
                            outBuf[i] = lutBuf[Int(inBuf[i])]
                            i += 1
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers de Contexto

    private func shouldReuseContext(width: Int, height: Int, samples: Int) -> Bool {
        return width == lastContextWidth &&
               height == lastContextHeight &&
               samples == lastSamplesPerPixel
    }

    private func resetImage() {
        bitmapContext = nil
        bitmapImage = nil
    }

    // MARK: - GPU (stub)

    private func processPixelsGPU(inputPixels: UnsafePointer<UInt16>,
                                  outputPixels: UnsafeMutablePointer<UInt8>,
                                  pixelCount: Int,
                                  winMin: Int,
                                  winMax: Int) -> Bool {
        // Integração com Metal/Accelerate pode entrar aqui.
        return false
    }
}
#endif
