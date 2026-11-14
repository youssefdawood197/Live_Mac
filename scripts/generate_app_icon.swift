#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

func createIconImage(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    ctx.saveGState()

    // 1. Margins for standard macOS icon grid (82.4% scale)
    let margin = size * 0.088
    let iconRect = CGRect(x: margin, y: margin, width: size - 2 * margin, height: size - 2 * margin)
    let cornerRadius = iconRect.width * 0.224 // macOS standard squircle radius

    // 2. Drop Shadow behind squircle
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.025), blur: size * 0.05, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    let squirclePath = CGPath(roundedRect: iconRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.addPath(squirclePath)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // 3. Clip to Squircle for Gradient Fill
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()

    // Vibrant Winter Cosmic Gradient (Indigo -> Electric Azure -> Ice Cyan)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.28, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.18, green: 0.35, blue: 0.75, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.25, green: 0.65, blue: 0.95, alpha: 1.0).cgColor
    ] as CFArray
    let locations: [CGFloat] = [0.0, 0.55, 1.0]
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
        ctx.drawLinearGradient(gradient, start: CGPoint(x: iconRect.midX, y: iconRect.minY), end: CGPoint(x: iconRect.midX, y: iconRect.maxY), options: [])
    }

    // Frosted Glass Highlight at Top
    let highlightRect = CGRect(x: iconRect.minX, y: iconRect.midY, width: iconRect.width, height: iconRect.height * 0.5)
    let highlightColors = [
        NSColor.white.withAlphaComponent(0.25).cgColor,
        NSColor.white.withAlphaComponent(0.0).cgColor
    ] as CFArray
    if let highlightGrad = CGGradient(colorsSpace: colorSpace, colors: highlightColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(highlightGrad, start: CGPoint(x: highlightRect.midX, y: highlightRect.maxY), end: CGPoint(x: highlightRect.midX, y: highlightRect.minY), options: [])
    }

    // Border stroke
    ctx.addPath(squirclePath)
    ctx.setLineWidth(size * 0.015)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.3).cgColor)
    ctx.strokePath()

    // 4. Draw Center Emblem: Snowflake + Lively Sparkle
    let centerX = iconRect.midX
    let centerY = iconRect.midY
    let radius = iconRect.width * 0.30

    ctx.saveGState()
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.01), blur: size * 0.03, color: NSColor(calibratedRed: 0.4, green: 0.8, blue: 1.0, alpha: 0.7).cgColor)

    // 6-Fold Snowflake Branches
    for i in 0..<6 {
        let angle = CGFloat(i) * (.pi / 3.0)
        let cosA = cos(angle)
        let sinA = sin(angle)

        // Main spine
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(size * 0.032)
        ctx.move(to: CGPoint(x: centerX, y: centerY))
        let endX = centerX + radius * cosA
        let endY = centerY + radius * sinA
        ctx.addLine(to: CGPoint(x: endX, y: endY))
        ctx.strokePath()

        // Branch V-barbs at 55% length
        let barbStartDist = radius * 0.52
        let bx = centerX + barbStartDist * cosA
        let by = centerY + barbStartDist * sinA

        let barbAngle1 = angle + .pi / 4.0
        let barbAngle2 = angle - .pi / 4.0
        let barbLen = radius * 0.32

        ctx.setLineWidth(size * 0.022)
        ctx.move(to: CGPoint(x: bx, y: by))
        ctx.addLine(to: CGPoint(x: bx + barbLen * cos(barbAngle1), y: by + barbLen * sin(barbAngle1)))
        ctx.move(to: CGPoint(x: bx, y: by))
        ctx.addLine(to: CGPoint(x: bx + barbLen * cos(barbAngle2), y: by + barbLen * sin(barbAngle2)))
        ctx.strokePath()

        // Outer tip diamond/hex node
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillEllipse(in: CGRect(x: endX - size * 0.02, y: endY - size * 0.02, width: size * 0.04, height: size * 0.04))
    }

    // Center Core Jewel
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillEllipse(in: CGRect(x: centerX - size * 0.06, y: centerY - size * 0.06, width: size * 0.12, height: size * 0.12))

    ctx.setFillColor(NSColor(calibratedRed: 0.2, green: 0.55, blue: 0.95, alpha: 1.0).cgColor)
    ctx.fillEllipse(in: CGRect(x: centerX - size * 0.035, y: centerY - size * 0.035, width: size * 0.07, height: size * 0.07))

    ctx.restoreGState() // Restore shadow
    ctx.restoreGState() // Restore clip
    ctx.restoreGState() // Restore main state

    image.unlockFocus()
    return image
}

func savePNG(image: NSImage, path: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to convert image to PNG for path: \(path)")
    }
    try! png.write(to: URL(fileURLWithPath: path))
}

let fileManager = FileManager.default
let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
let projectRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let iconsetDir = projectRoot.appendingPathComponent("build/AppIcon.iconset")
let resourcesDir = projectRoot.appendingPathComponent("Resources")
let outputICNS = resourcesDir.appendingPathComponent("AppIcon.icns")

try? fileManager.removeItem(at: iconsetDir)
try! fileManager.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

print("==> Generating multi-resolution icon assets in AppIcon.iconset...")
let specs: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (filename, size) in specs {
    let img = createIconImage(size: size)
    let outPath = iconsetDir.appendingPathComponent(filename).path
    savePNG(image: img, path: outPath)
}

print("==> Compiling AppIcon.icns via iconutil...")
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetDir.path, "-o", outputICNS.path]
try! process.run()
process.waitUntilExit()

if process.terminationStatus == 0 && fileManager.fileExists(atPath: outputICNS.path) {
    let size = (try? fileManager.attributesOfItem(atPath: outputICNS.path)[.size] as? Int) ?? 0
    print("==========================================================")
    print(" Successfully generated AppIcon.icns (\(size / 1024) KB)!")
    print(" Location: \(outputICNS.path)")
    print("==========================================================")
} else {
    print("Error: iconutil failed with code \(process.terminationStatus)")
    exit(1)
}
