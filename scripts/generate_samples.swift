import Foundation
import AVFoundation
import CoreGraphics
import CoreVideo

let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let targetSamplesDirectory = projectRoot.appendingPathComponent("Resources/Samples", isDirectory: true)

print("Populating sample assets into: \(targetSamplesDirectory.path)...")

let videoURL = targetSamplesDirectory.appendingPathComponent("sample_loop.mp4")
let fileManager = FileManager.default

if !fileManager.fileExists(atPath: targetSamplesDirectory.path) {
    try fileManager.createDirectory(at: targetSamplesDirectory, withIntermediateDirectories: true)
}
if fileManager.fileExists(atPath: videoURL.path) {
    try fileManager.removeItem(at: videoURL)
}

let width = 320
let height = 180
let fps: Int32 = 24
let duration: Double = 1.0
let bitrate = 50_000

let assetWriter = try AVAssetWriter(outputURL: videoURL, fileType: .mp4)

let compressionProperties: [String: Any] = [
    AVVideoAverageBitRateKey: bitrate,
    AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel,
    AVVideoMaxKeyFrameIntervalKey: fps,
    AVVideoExpectedSourceFrameRateKey: fps
]

let videoSettings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: width,
    AVVideoHeightKey: height,
    AVVideoCompressionPropertiesKey: compressionProperties
]

let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
writerInput.expectsMediaDataInRealTime = false

let sourcePixelBufferAttributes: [String: Any] = [
    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
    kCVPixelBufferWidthKey as String: width,
    kCVPixelBufferHeightKey as String: height,
    kCVPixelBufferCGImageCompatibilityKey as String: true,
    kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
]

let adaptor = AVAssetWriterInputPixelBufferAdaptor(
    assetWriterInput: writerInput,
    sourcePixelBufferAttributes: sourcePixelBufferAttributes
)

guard assetWriter.canAdd(writerInput) else {
    print("Cannot add input")
    exit(1)
}
assetWriter.add(writerInput)

guard assetWriter.startWriting() else {
    print("Failed to start writing: \(String(describing: assetWriter.error))")
    exit(1)
}
assetWriter.startSession(atSourceTime: .zero)

let totalFrames = Int(Double(fps) * duration)
let colorSpace = CGColorSpaceCreateDeviceRGB()

for frame in 0..<totalFrames {
    while !writerInput.isReadyForMoreMediaData {
        usleep(5000)
    }

    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32ARGB,
        sourcePixelBufferAttributes as CFDictionary,
        &pixelBuffer
    )
    guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
        print("Failed to create pixel buffer")
        exit(1)
    }

    CVPixelBufferLockBaseAddress(buffer, [])
    if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        if let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) {
            let progress = Double(frame) / Double(totalFrames)
            let angle = progress * 2.0 * .pi

            let startColor = CGColor(
                red: CGFloat(0.45 + 0.45 * sin(angle)),
                green: CGFloat(0.45 + 0.45 * sin(angle + 2.0 * .pi / 3.0)),
                blue: CGFloat(0.45 + 0.45 * sin(angle + 4.0 * .pi / 3.0)),
                alpha: 1.0
            )
            let endColor = CGColor(
                red: CGFloat(0.3 + 0.3 * sin(angle + .pi)),
                green: CGFloat(0.3 + 0.3 * sin(angle + 5.0 * .pi / 3.0)),
                blue: CGFloat(0.3 + 0.3 * sin(angle + .pi / 3.0)),
                alpha: 1.0
            )

            if let gradient = CGGradient(colorsSpace: colorSpace, colors: [startColor, endColor] as CFArray, locations: [0.0, 1.0]) {
                context.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: CGFloat(width), y: CGFloat(height)),
                    options: []
                )
            }

            let centerX = CGFloat(width) / 2.0
            let centerY = CGFloat(height) / 2.0
            let radius = CGFloat(16.0 + 10.0 * sin(angle))

            context.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.9))
            context.fillEllipse(in: CGRect(x: centerX - radius, y: centerY - radius, width: radius * 2, height: radius * 2))

            let ringRadius = CGFloat(32.0 + 8.0 * cos(angle))
            context.setStrokeColor(CGColor(red: 0.9, green: 0.95, blue: 1.0, alpha: 0.5))
            context.setLineWidth(2.0)
            context.strokeEllipse(in: CGRect(x: centerX - ringRadius, y: centerY - ringRadius, width: ringRadius * 2, height: ringRadius * 2))
        }
    }
    CVPixelBufferUnlockBaseAddress(buffer, [])

    let presentationTime = CMTime(value: CMTimeValue(frame), timescale: fps)
    let appended = adaptor.append(buffer, withPresentationTime: presentationTime)
    if !appended {
        print("Failed to append frame \(frame): \(String(describing: assetWriter.error))")
        exit(1)
    }
}

writerInput.markAsFinished()

let semaphore = DispatchSemaphore(value: 0)
assetWriter.finishWriting {
    semaphore.signal()
}
semaphore.wait()

let videoAttrs = try FileManager.default.attributesOfItem(atPath: videoURL.path)
let videoSize = (videoAttrs[.size] as? NSNumber)?.int64Value ?? 0
print("✓ Sample Video generated at: \(videoURL.path) (\(videoSize) bytes, \(Double(videoSize)/1024.0) KB)")
print("Sample video generation complete!")
