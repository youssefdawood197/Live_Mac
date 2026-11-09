import Foundation
import AVFoundation
import CoreGraphics
import CoreVideo

/// Generates lightweight, looping video and web canvas sample assets without external tools.
public final class SampleAssetGenerator: Sendable {

    public static let defaultVideoFileName = "sample_loop.mp4"
    public static let defaultCanvasDirectoryName = "sample_canvas"
    public static let defaultCanvasIndexFileName = "index.html"
    public static let maxExpectedVideoSizeBytes: Int64 = 15 * 1024 // 15 KB

    public init() {}

    /// Generates a valid, looping H.264 MP4 video file under 15 KB.
    ///
    /// - Parameters:
    ///   - destinationURL: Target file URL for the MP4 output.
    ///   - duration: Duration in seconds (default 1.0s).
    ///   - fps: Frames per second (default 24).
    ///   - size: Resolution dimensions (default 320x180).
    ///   - bitrate: Average bitrate in bps (default 50,000 bps).
    /// - Returns: The destination URL of the written video file.
    @discardableResult
    public func generateSampleVideo(
        at destinationURL: URL,
        duration: Double = 1.0,
        fps: Int32 = 24,
        size: CGSize = CGSize(width: 320, height: 180),
        bitrate: Int = 50_000
    ) async throws -> URL {
        let fileManager = FileManager.default
        let directory = destinationURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        let assetWriter = try AVAssetWriter(outputURL: destinationURL, fileType: .mp4)

        let width = Int(size.width)
        let height = Int(size.height)

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
            throw NSError(
                domain: "SampleAssetGenerator",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot add AVAssetWriterInput to AVAssetWriter"]
            )
        }
        assetWriter.add(writerInput)

        guard assetWriter.startWriting() else {
            throw assetWriter.error ?? NSError(
                domain: "SampleAssetGenerator",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to start AVAssetWriter writing"]
            )
        }
        assetWriter.startSession(atSourceTime: .zero)

        let totalFrames = Int(Double(fps) * duration)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        for frame in 0..<totalFrames {
            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000)
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
                throw NSError(
                    domain: "SampleAssetGenerator",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to allocate CVPixelBuffer"]
                )
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
                    // Cyclic parameter from 0.0 to 2*PI for seamless loop
                    let progress = Double(frame) / Double(totalFrames)
                    let angle = progress * 2.0 * .pi

                    // Vibrant animated gradient background
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

                    // Pulsing luminous core
                    let centerX = CGFloat(width) / 2.0
                    let centerY = CGFloat(height) / 2.0
                    let radius = CGFloat(16.0 + 10.0 * sin(angle))

                    context.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.9))
                    context.fillEllipse(in: CGRect(x: centerX - radius, y: centerY - radius, width: radius * 2, height: radius * 2))

                    // Outer glowing ring
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
                throw assetWriter.error ?? NSError(
                    domain: "SampleAssetGenerator",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to append pixel buffer for frame \(frame)"]
                )
            }
        }

        writerInput.markAsFinished()
        await assetWriter.finishWriting()

        if assetWriter.status == .failed {
            throw assetWriter.error ?? NSError(
                domain: "SampleAssetGenerator",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "AVAssetWriter failed to complete writing"]
            )
        }

        return destinationURL
    }

    /// Generates a responsive, vibrant HTML5/Canvas animated wallpaper in the target directory.
    ///
    /// - Parameter destinationDirectoryURL: Folder where `index.html` will be written.
    /// - Returns: URL of the created `index.html`.
    @discardableResult
    public func generateSampleCanvas(at destinationDirectoryURL: URL) throws -> URL {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: destinationDirectoryURL.path) {
            try fileManager.createDirectory(at: destinationDirectoryURL, withIntermediateDirectories: true)
        }

        let indexHTMLURL = destinationDirectoryURL.appendingPathComponent(Self.defaultCanvasIndexFileName)
        try Self.canvasHTMLContent.write(to: indexHTMLURL, atomically: true, encoding: .utf8)
        return indexHTMLURL
    }

    /// Generates all sample assets (video loop and canvas directory) into a base directory.
    ///
    /// - Parameter baseDirectoryURL: Target directory.
    /// - Returns: A tuple of the generated video URL and canvas directory URL.
    public func generateAllSamples(in baseDirectoryURL: URL) async throws -> (videoURL: URL, canvasDirectoryURL: URL) {
        let videoURL = baseDirectoryURL.appendingPathComponent(Self.defaultVideoFileName)
        let canvasDir = baseDirectoryURL.appendingPathComponent(Self.defaultCanvasDirectoryName)

        let genVideoURL = try await generateSampleVideo(at: videoURL)
        let _ = try generateSampleCanvas(at: canvasDir)

        return (genVideoURL, canvasDir)
    }

    /// Self-contained HTML5 Canvas source code with embedded CSS and JavaScript.
    public static let canvasHTMLContent = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Lively Waves - Canvas Wallpaper</title>
      <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        html, body {
          width: 100%; height: 100%; overflow: hidden;
          background: #0a0e17; user-select: none; -webkit-user-select: none;
        }
        canvas {
          display: block; width: 100vw; height: 100vh;
          position: absolute; top: 0; left: 0;
        }
      </style>
    </head>
    <body>
      <canvas id="wallpaperCanvas"></canvas>
      <script>
        (function() {
          const canvas = document.getElementById('wallpaperCanvas');
          const ctx = canvas.getContext('2d');
          let width, height, dpr;
          let animationFrameId;
          let tick = 0;

          const mouse = { x: null, y: null, radius: 150, active: false };

          const waves = [
            { amplitude: 45, frequency: 0.008, speed: 0.025, color: 'rgba(56, 189, 248, 0.45)', baseOffset: 0.45 },
            { amplitude: 60, frequency: 0.005, speed: 0.018, color: 'rgba(168, 85, 247, 0.40)', baseOffset: 0.52 },
            { amplitude: 35, frequency: 0.012, speed: 0.032, color: 'rgba(236, 72, 153, 0.35)', baseOffset: 0.58 },
            { amplitude: 50, frequency: 0.007, speed: 0.014, color: 'rgba(16, 185, 129, 0.30)', baseOffset: 0.65 }
          ];

          const particleCount = 60;
          const particles = [];

          class Particle {
            constructor() { this.reset(true); }
            reset(randomY = false) {
              this.x = Math.random() * (width || window.innerWidth);
              this.y = randomY ? Math.random() * (height || window.innerHeight) : (height || window.innerHeight) + 10;
              this.radius = Math.random() * 2.5 + 1.0;
              this.vx = (Math.random() - 0.5) * 0.8;
              this.vy = -(Math.random() * 0.8 + 0.3);
              this.hue = Math.random() * 60 + 180;
              this.alpha = Math.random() * 0.7 + 0.3;
              this.pulse = Math.random() * Math.PI;
            }
            update() {
              this.x += this.vx;
              this.y += this.vy;
              this.pulse += 0.03;
              if (mouse.active && mouse.x !== null) {
                const dx = this.x - mouse.x;
                const dy = this.y - mouse.y;
                const dist = Math.hypot(dx, dy);
                if (dist < mouse.radius && dist > 0) {
                  const force = (mouse.radius - dist) / mouse.radius;
                  this.x += (dx / dist) * force * 5;
                  this.y += (dy / dist) * force * 5;
                }
              }
              if (this.y < -10 || this.x < -10 || this.x > width + 10) { this.reset(false); }
            }
            draw() {
              const currentRadius = this.radius * (1 + 0.25 * Math.sin(this.pulse));
              ctx.beginPath();
              ctx.arc(this.x, this.y, currentRadius, 0, Math.PI * 2);
              ctx.fillStyle = `hsla(${this.hue}, 85%, 65%, ${this.alpha})`;
              ctx.shadowBlur = 12;
              ctx.shadowColor = `hsla(${this.hue}, 90%, 60%, 0.8)`;
              ctx.fill();
              ctx.shadowBlur = 0;
            }
          }

          function resize() {
            dpr = window.devicePixelRatio || 1;
            width = window.innerWidth;
            height = window.innerHeight;
            canvas.width = width * dpr;
            canvas.height = height * dpr;
            ctx.scale(dpr, dpr);
            if (particles.length === 0) {
              for (let i = 0; i < particleCount; i++) particles.push(new Particle());
            }
          }

          function drawBackground() {
            const bgGradient = ctx.createLinearGradient(0, 0, width, height);
            bgGradient.addColorStop(0, '#0a0e17');
            bgGradient.addColorStop(0.5, '#0f172a');
            bgGradient.addColorStop(1, '#1e1b4b');
            ctx.fillStyle = bgGradient;
            ctx.fillRect(0, 0, width, height);
          }

          function drawWaves() {
            waves.forEach((wave) => {
              ctx.beginPath();
              const baseHeight = height * wave.baseOffset;
              ctx.moveTo(0, height);
              ctx.lineTo(0, baseHeight);
              for (let x = 0; x <= width; x += 8) {
                let waveY = Math.sin(x * wave.frequency + tick * wave.speed) * wave.amplitude;
                waveY += Math.cos(x * wave.frequency * 0.5 + tick * wave.speed * 0.7) * (wave.amplitude * 0.4);
                if (mouse.active && mouse.x !== null) {
                  const dx = x - mouse.x;
                  const dist = Math.abs(dx);
                  if (dist < mouse.radius) {
                    const influence = Math.cos((dist / mouse.radius) * (Math.PI / 2));
                    waveY += (mouse.y - baseHeight) * influence * 0.25;
                  }
                }
                ctx.lineTo(x, baseHeight + waveY);
              }
              ctx.lineTo(width, height);
              ctx.closePath();
              ctx.fillStyle = wave.color;
              ctx.fill();
            });
          }

          function drawConnections() {
            for (let i = 0; i < particles.length; i++) {
              for (let j = i + 1; j < particles.length; j++) {
                const dx = particles[i].x - particles[j].x;
                const dy = particles[i].y - particles[j].y;
                const dist = Math.hypot(dx, dy);
                if (dist < 90) {
                  const alpha = (1 - dist / 90) * 0.25;
                  ctx.beginPath();
                  ctx.strokeStyle = `rgba(147, 197, 253, ${alpha})`;
                  ctx.lineWidth = 0.8;
                  ctx.moveTo(particles[i].x, particles[i].y);
                  ctx.lineTo(particles[j].x, particles[j].y);
                  ctx.stroke();
                }
              }
            }
          }

          function animate() {
            tick++;
            ctx.clearRect(0, 0, width, height);
            drawBackground();
            drawWaves();
            drawConnections();
            particles.forEach(p => { p.update(); p.draw(); });
            animationFrameId = requestAnimationFrame(animate);
          }

          window.addEventListener('resize', resize);
          window.addEventListener('mousemove', (e) => {
            mouse.x = e.clientX; mouse.y = e.clientY; mouse.active = true;
          });
          window.addEventListener('mouseleave', () => { mouse.active = false; });
          window.addEventListener('mousedown', (e) => {
            for (let i = 0; i < 8; i++) {
              const p = new Particle();
              p.x = e.clientX; p.y = e.clientY;
              p.vx = (Math.random() - 0.5) * 6; p.vy = (Math.random() - 0.5) * 6;
              p.radius = Math.random() * 4 + 2;
              particles.push(p);
              if (particles.length > particleCount + 20) particles.shift();
            }
          });

          document.addEventListener('visibilitychange', () => {
            if (document.hidden) { cancelAnimationFrame(animationFrameId); }
            else { animationFrameId = requestAnimationFrame(animate); }
          });

          resize();
          animate();
        })();
      </script>
    </body>
    </html>
    """
}
