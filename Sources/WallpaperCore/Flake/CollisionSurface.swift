import Foundation
import CoreGraphics

/// Represents a horizontal collision surface ledge where falling snow can settle and accumulate.
public struct CollisionSurface: Equatable, Identifiable, Sendable {
    /// Window or surface identifier (0 represents display screen bottom).
    public let id: CGWindowID

    /// Full bounding box of the window in Cocoa screen coordinates.
    public let frame: CGRect

    /// Y coordinate of the top ledge where snow rests.
    public let topEdgeY: CGFloat

    /// Leftmost horizontal boundary.
    public let minX: CGFloat

    /// Rightmost horizontal boundary.
    public let maxX: CGFloat

    /// Whether this ledge corresponds to the macOS Dock.
    public let isDock: Bool

    /// Width of the surface ledge.
    public var width: CGFloat {
        max(0, maxX - minX)
    }

    public init(
        id: CGWindowID,
        frame: CGRect,
        topEdgeY: CGFloat,
        minX: CGFloat,
        maxX: CGFloat,
        isDock: Bool = false
    ) {
        self.id = id
        self.frame = frame
        self.topEdgeY = topEdgeY
        self.minX = minX
        self.maxX = maxX
        self.isDock = isDock
    }

    /// Determines if an X coordinate falls horizontally within this surface ledge.
    public func containsX(_ x: CGFloat) -> Bool {
        return x >= minX && x <= maxX
    }
}

/// Column-based heightmap tracking accumulated snow depth across a collision surface.
/// Binned into discrete columns of 10 points width.
public struct SurfaceHeightmap: Equatable, Sendable {
    public static let binWidth: CGFloat = 10.0

    public let surfaceID: CGWindowID
    public var bins: [CGFloat]
    public var anchorPosition: CGPoint // (minX, topEdgeY)

    public init(surfaceID: CGWindowID, width: CGFloat, anchorPosition: CGPoint = .zero) {
        self.surfaceID = surfaceID
        let count = max(1, Int(ceil(width / Self.binWidth)))
        self.bins = Array(repeating: 0.0, count: count)
        self.anchorPosition = anchorPosition
    }

    public init(surfaceID: CGWindowID, bins: [CGFloat], anchorPosition: CGPoint = .zero) {
        self.surfaceID = surfaceID
        self.bins = bins
        self.anchorPosition = anchorPosition
    }

    public var averageDepth: CGFloat {
        guard !bins.isEmpty else { return 0 }
        return bins.reduce(0, +) / CGFloat(bins.count)
    }

    public var maxDepth: CGFloat {
        bins.max() ?? 0
    }

    /// Resizes horizontal bin count while preserving existing accumulation depth.
    public mutating func resize(to newWidth: CGFloat) {
        let targetCount = max(1, Int(ceil(newWidth / Self.binWidth)))
        guard targetCount != bins.count else { return }
        if targetCount > bins.count {
            bins.append(contentsOf: Array(repeating: 0.0, count: targetCount - bins.count))
        } else {
            bins = Array(bins.prefix(targetCount))
        }
    }

    /// Accumulates snow depth into bins with a strict surface height cap.
    public mutating func accumulate(
        rate: CGFloat,
        maxCap: CGFloat,
        windAngleDegrees: Double = 90.0,
        windSpeed: Double = 1.0
    ) {
        // Calculate wind drift bias across bins
        let rad = CGFloat(windAngleDegrees) * .pi / 180.0
        let windDrift = cos(rad) * CGFloat(min(1.0, windSpeed / 3.0))

        for i in 0..<bins.count {
            if bins[i] < maxCap {
                let normX = CGFloat(i) / CGFloat(max(1, bins.count - 1)) - 0.5
                let bias = 1.0 + (windDrift * normX * 0.4)
                let variation = CGFloat.random(in: 0.8...1.2) * max(0.5, bias)
                bins[i] = min(maxCap, bins[i] + rate * variation)
            }
        }
    }

    /// Applies 3-point angle of repose smoothing convolution:
    /// (bins[i-1] + 2*bins[i] + bins[i+1]) / 4
    /// Uses double-buffering to prevent asymmetric rightward skewing.
    public mutating func smoothAngleOfRepose(maxCap: CGFloat = .infinity) {
        bins = Self.convolve(bins: bins, maxCap: maxCap)
    }

    public static func convolve(bins: [CGFloat], maxCap: CGFloat = .infinity) -> [CGFloat] {
        guard bins.count >= 2 else { return bins }
        var result = bins
        let count = bins.count

        // Taper boundary edges
        result[0] = min(maxCap, (2.0 * bins[0] + bins[1]) / 3.0)
        result[count - 1] = min(maxCap, (bins[count - 2] + 2.0 * bins[count - 1]) / 3.0)

        // 3-point double-buffered convolution
        if count >= 3 {
            for i in 1..<(count - 1) {
                let smoothed = (bins[i - 1] + 2.0 * bins[i] + bins[i + 1]) / 4.0
                result[i] = min(maxCap, smoothed)
            }
        }
        return result
    }

    public static func convolve(bins: [Double], maxCap: Double = .infinity) -> [Double] {
        let cgBins = bins.map { CGFloat($0) }
        let result = convolve(bins: cgBins, maxCap: CGFloat(maxCap))
        return result.map { Double($0) }
    }

    /// Updates anchor position when window moves and returns translation delta (dx, dy).
    public mutating func reanchor(newAnchor: CGPoint) -> CGVector {
        let delta = CGVector(dx: newAnchor.x - anchorPosition.x, dy: newAnchor.y - anchorPosition.y)
        anchorPosition = newAnchor
        return delta
    }
}
