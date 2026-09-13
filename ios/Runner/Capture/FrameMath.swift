import CoreGraphics
import CoreImage
import CoreVideo
import Foundation

/// A small downsampled grayscale buffer used for all live-analysis math.
struct LumaFrame {
    let width: Int
    let height: Int
    let pixels: [Int]
}

/// Classical, on-device frame analysis (SPEC 9.3). Mirrors
/// `android/.../capture/FrameMath.kt` and
/// `lib/data/services/scanner/adapters/dart_page_detection_provider.dart` so
/// behavior is consistent across platforms and providers. Intentionally
/// cheap: it must run at live-preview frame rate on a downsampled buffer.
enum FrameMath {
    static let targetDim = 480

    /// Extracts a downsampled grayscale buffer directly from the Y plane of
    /// a `kCVPixelFormatType_420YpCbCr8BiPlanarFullRange` (or similar
    /// bi-planar YUV) pixel buffer — no RGB conversion needed for luma.
    static func extractLuma(from pixelBuffer: CVPixelBuffer) -> LumaFrame? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let planeIndex = CVPixelBufferGetPlaneCount(pixelBuffer) > 0 ? 0 : -1
        guard planeIndex == 0,
              let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)
        else { return nil }

        let srcWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let srcHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

        return downsample(
            width: srcWidth,
            height: srcHeight,
            get: { x, y in Int(buffer[y * bytesPerRow + x]) }
        )
    }

    /// Same extraction path for an already-decoded still image (captured
    /// photo file).
    static func extractLuma(from cgImage: CGImage) -> LumaFrame? {
        let srcWidth = cgImage.width
        let srcHeight = cgImage.height
        var pixelData = [UInt8](repeating: 0, count: srcWidth * srcHeight)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: &pixelData,
            width: srcWidth,
            height: srcHeight,
            bitsPerComponent: 8,
            bytesPerRow: srcWidth,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: srcWidth, height: srcHeight))

        return downsample(
            width: srcWidth,
            height: srcHeight,
            get: { x, y in Int(pixelData[y * srcWidth + x]) }
        )
    }

    private static func downsample(width srcWidth: Int, height srcHeight: Int, get: (Int, Int) -> Int) -> LumaFrame {
        let scale = Double(targetDim) / Double(max(srcWidth, srcHeight))
        let dstWidth = max(1, Int(Double(srcWidth) * scale))
        let dstHeight = max(1, Int(Double(srcHeight) * scale))

        var pixels = [Int](repeating: 0, count: dstWidth * dstHeight)
        for dy in 0..<dstHeight {
            let sy = min(srcHeight - 1, Int(Double(dy) / scale))
            for dx in 0..<dstWidth {
                let sx = min(srcWidth - 1, Int(Double(dx) / scale))
                pixels[dy * dstWidth + dx] = get(sx, sy)
            }
        }
        return LumaFrame(width: dstWidth, height: dstHeight, pixels: pixels)
    }

    static func averageLuminance(_ frame: LumaFrame) -> Double {
        guard !frame.pixels.isEmpty else { return 0 }
        return Double(frame.pixels.reduce(0, +)) / Double(frame.pixels.count)
    }

    /// Laplacian-variance sharpness estimate — same technique as the
    /// Android/Dart baselines, for consistent "in focus" thresholds.
    static func sharpness(_ frame: LumaFrame) -> Double {
        let w = frame.width
        let h = frame.height
        guard w >= 3, h >= 3 else { return 0 }

        var sum = 0.0
        var sumSq = 0.0
        var count = 0
        for y in stride(from: 1, to: h - 1, by: 2) {
            for x in stride(from: 1, to: w - 1, by: 2) {
                let c = frame.pixels[y * w + x]
                let l = frame.pixels[y * w + x - 1]
                let r = frame.pixels[y * w + x + 1]
                let t = frame.pixels[(y - 1) * w + x]
                let b = frame.pixels[(y + 1) * w + x]
                let lap = Double(4 * c - l - r - t - b)
                sum += lap
                sumSq += lap * lap
                count += 1
            }
        }
        guard count > 0 else { return 0 }
        let mean = sum / Double(count)
        return sumSq / Double(count) - mean * mean
    }

    /// Estimates a document quadrilateral via row/column edge-energy
    /// projection profiles (matches the Android/Dart classical baseline).
    /// Returns normalized (0..1) corner coordinates, or nil if the edge
    /// signal is too weak to trust.
    static func detectQuad(_ frame: LumaFrame) -> Quad? {
        let w = frame.width
        let h = frame.height
        guard w >= 8, h >= 8 else { return nil }

        var rowEnergy = [Double](repeating: 0, count: h)
        var colEnergy = [Double](repeating: 0, count: w)
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let gx = abs(frame.pixels[y * w + x + 1] - frame.pixels[y * w + x - 1])
                let gy = abs(frame.pixels[(y + 1) * w + x] - frame.pixels[(y - 1) * w + x])
                let mag = Double(gx + gy)
                rowEnergy[y] += mag
                colEnergy[x] += mag
            }
        }

        let rowThreshold = (rowEnergy.max() ?? 0) * 0.35
        let colThreshold = (colEnergy.max() ?? 0) * 0.35

        var top = 0
        while top < h - 1, rowEnergy[top] < rowThreshold { top += 1 }
        var bottom = h - 1
        while bottom > 0, rowEnergy[bottom] < rowThreshold { bottom -= 1 }
        var left = 0
        while left < w - 1, colEnergy[left] < colThreshold { left += 1 }
        var right = w - 1
        while right > 0, colEnergy[right] < colThreshold { right -= 1 }

        guard Double(right - left) >= Double(w) * 0.3, Double(bottom - top) >= Double(h) * 0.3 else {
            // Not enough confident edge signal — the caller falls back to
            // a full-frame quad and manual correction rather than a guess.
            return nil
        }

        let l = Double(left) / Double(w)
        let r = Double(right) / Double(w)
        let t = Double(top) / Double(h)
        let b = Double(bottom) / Double(h)

        return Quad(
            topLeft: Point2D(x: l, y: t),
            topRight: Point2D(x: r, y: t),
            bottomRight: Point2D(x: r, y: b),
            bottomLeft: Point2D(x: l, y: b)
        )
    }

    /// Mean absolute per-pixel luminance delta between two same-size frames.
    static func motionScore(previous: LumaFrame?, current: LumaFrame) -> Double {
        guard let previous, previous.width == current.width, previous.height == current.height else {
            return 0
        }
        var sum = 0
        for i in current.pixels.indices {
            sum += abs(current.pixels[i] - previous.pixels[i])
        }
        return Double(sum) / Double(current.pixels.count)
    }
}

struct Point2D {
    let x: Double
    let y: Double

    var asDict: [String: Double] { ["x": x, "y": y] }
}

struct Quad {
    let topLeft: Point2D
    let topRight: Point2D
    let bottomRight: Point2D
    let bottomLeft: Point2D

    var asDict: [String: [String: Double]] {
        [
            "topLeft": topLeft.asDict,
            "topRight": topRight.asDict,
            "bottomRight": bottomRight.asDict,
            "bottomLeft": bottomLeft.asDict,
        ]
    }
}
