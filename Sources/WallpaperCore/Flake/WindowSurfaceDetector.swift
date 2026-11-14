import AppKit
import CoreGraphics
import Foundation

/// Defines the contract for querying on-screen collision surfaces across displays.
public protocol WindowSurfaceDetectorProtocol: Sendable {
    func detectSurfaces(screenRect: CGRect, visibleFrame: CGRect) -> [CollisionSurface]
    func detectSurfaces(
        screenRect: CGRect,
        visibleFrame: CGRect,
        primaryScreenHeight: CGFloat?,
        config: FlakeConfiguration
    ) -> [CollisionSurface]
}

extension WindowSurfaceDetectorProtocol {
    public func detectSurfaces(screenRect: CGRect, visibleFrame: CGRect) -> [CollisionSurface] {
        return detectSurfaces(
            screenRect: screenRect,
            visibleFrame: visibleFrame,
            primaryScreenHeight: nil,
            config: FlakeConfiguration()
        )
    }
}

/// Analyzes on-screen window coordinates to extract horizontal ledges where snow can settle and pile up.
///
/// Uses zero-TCC Quartz Window Services via `WindowInfoProviderProtocol`.
public final class WindowSurfaceDetector: WindowSurfaceDetectorProtocol, @unchecked Sendable {
    private let windowProvider: WindowInfoProviderProtocol

    public init(windowProvider: WindowInfoProviderProtocol = SystemWindowInfoProvider()) {
        self.windowProvider = windowProvider
    }

    /// Primary protocol implementation with custom parameters.
    public func detectSurfaces(
        screenRect: CGRect,
        visibleFrame: CGRect,
        primaryScreenHeight: CGFloat? = nil,
        config: FlakeConfiguration = FlakeConfiguration()
    ) -> [CollisionSurface] {
        var surfaces: [CollisionSurface] = []
        let refHeight = primaryScreenHeight ?? (screenRect.height > 0 ? screenRect.height : (NSScreen.screens.first?.frame.height ?? 1080))

        // Feature 5: Bottom Display Shelf (id: 0, spanning width)
        if config.accumulateOnScreenBottom {
            surfaces.append(CollisionSurface(
                id: 0,
                frame: CGRect(x: screenRect.minX, y: screenRect.minY, width: screenRect.width, height: 1),
                topEdgeY: screenRect.minY,
                minX: screenRect.minX,
                maxX: screenRect.maxX,
                isDock: false
            ))
        }

        guard config.accumulateOnWindows || config.accumulateOnDock else {
            return surfaces
        }

        let windows = windowProvider.copyWindowInfoList()
        let currentPID = ProcessInfo.processInfo.processIdentifier

        var foundDockWindow = false
        var occludingFrames: [CGRect] = []

        // Windows from CGWindowListCopyWindowInfo are in front-to-back z-order
        for win in windows {
            // Self-exclusion
            guard win.ownerPID != currentPID else { continue }

            // Feature 2: Zero-TCC Window Surface Filtering
            guard win.layer == 0, win.isOnScreen, win.alpha > 0.05 else { continue }

            let isDockWindow = win.ownerName.caseInsensitiveCompare("Dock") == .orderedSame
            if isDockWindow {
                foundDockWindow = true
                if !config.accumulateOnDock { continue }
            } else {
                guard win.bounds.width >= 120, win.bounds.height >= 80 else { continue }
                if !config.accumulateOnWindows { continue }
            }

            // Feature 3: Coordinate System Inversion (Quartz top-left to Cocoa bottom-left)
            let cocoaX = win.bounds.minX
            let cocoaTopY = refHeight - win.bounds.minY
            let cocoaBottomY = cocoaTopY - win.bounds.height
            let cocoaFrame = CGRect(x: cocoaX, y: cocoaBottomY, width: win.bounds.width, height: win.bounds.height)

            guard cocoaFrame.intersects(screenRect) else { continue }

            let clampedMinX = max(screenRect.minX, cocoaFrame.minX)
            let clampedMaxX = min(screenRect.maxX, cocoaFrame.maxX)
            guard clampedMaxX - clampedMinX >= 40 else { continue }

            // Feature 6: Window Occlusion Culling via 1D interval subtraction algorithm
            var visibleIntervals: [ClosedRange<CGFloat>] = [clampedMinX...clampedMaxX]

            for occluder in occludingFrames {
                // Check if occluder vertically covers the ledge
                if cocoaTopY >= (occluder.minY - 0.5) && cocoaTopY <= (occluder.maxY + 0.5) {
                    var nextIntervals: [ClosedRange<CGFloat>] = []
                    for interval in visibleIntervals {
                        let occMin = occluder.minX
                        let occMax = occluder.maxX

                        if occMax <= interval.lowerBound || occMin >= interval.upperBound {
                            // No horizontal overlap
                            nextIntervals.append(interval)
                        } else if occMin <= interval.lowerBound && occMax >= interval.upperBound {
                            // Entire interval covered by occluder -> drop
                            continue
                        } else if occMin > interval.lowerBound && occMax < interval.upperBound {
                            // Hole punched in middle -> split
                            nextIntervals.append(interval.lowerBound...occMin)
                            nextIntervals.append(occMax...interval.upperBound)
                        } else if occMin <= interval.lowerBound && occMax < interval.upperBound {
                            // Left side covered
                            nextIntervals.append(occMax...interval.upperBound)
                        } else if occMin > interval.lowerBound && occMax >= interval.upperBound {
                            // Right side covered
                            nextIntervals.append(interval.lowerBound...occMin)
                        }
                    }
                    visibleIntervals = nextIntervals
                }
            }

            // Candidate window body is an occluder for subsequent lower-z windows
            occludingFrames.append(cocoaFrame)

            // Filter remaining intervals: keep those >= 40pt
            let validIntervals = visibleIntervals.filter { ($0.upperBound - $0.lowerBound) >= 40 }
            guard !validIntervals.isEmpty else {
                // Top ledge completely occluded -> culled
                continue
            }

            // Select widest unoccluded segment
            let widest = validIntervals.max(by: { ($0.upperBound - $0.lowerBound) < ($1.upperBound - $1.lowerBound) })!

            surfaces.append(CollisionSurface(
                id: win.windowID,
                frame: cocoaFrame,
                topEdgeY: cocoaTopY,
                minX: widest.lowerBound,
                maxX: widest.upperBound,
                isDock: isDockWindow
            ))
        }

        // Feature 4: Dock Surface Extraction via visibleFrame inset (> 10pt) fallback
        if config.accumulateOnDock && !foundDockWindow {
            let bottomInset = visibleFrame.minY - screenRect.minY
            if bottomInset > 10 {
                surfaces.append(CollisionSurface(
                    id: CGWindowID.max - 10,
                    frame: CGRect(x: visibleFrame.minX, y: screenRect.minY, width: visibleFrame.width, height: bottomInset),
                    topEdgeY: visibleFrame.minY,
                    minX: visibleFrame.minX,
                    maxX: visibleFrame.maxX,
                    isDock: true
                ))
            }
        }

        return surfaces
    }

    /// Backwards-compatible convenience overload for callers and legacy tests.
    public func detectSurfaces(
        for screenFrame: CGRect,
        primaryScreenHeight: CGFloat? = nil,
        config: FlakeConfiguration = FlakeConfiguration()
    ) -> [CollisionSurface] {
        return detectSurfaces(
            screenRect: screenFrame,
            visibleFrame: screenFrame,
            primaryScreenHeight: primaryScreenHeight,
            config: config
        )
    }
}
