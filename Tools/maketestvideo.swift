// Generates a synthetic test video with a moving element so it is obvious
// whether the wallpaper is really playing (and not showing a static frame).
import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/duskpaper_test.mp4"
let url = URL(fileURLWithPath: outputPath)
try? FileManager.default.removeItem(at: url)

let width = 1280, height = 720, fps: Int32 = 30, frameCount = 180
let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: width,
    AVVideoHeightKey: height,
])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(
    assetWriterInput: input,
    sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
    ]
)
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)

let semaphore = DispatchSemaphore(value: 0)
var frame = 0
var finished = false

input.requestMediaDataWhenReady(on: DispatchQueue(label: "encoder")) {
    // The block is called repeatedly; only finish once every frame is queued.
    if finished { return }
    while input.isReadyForMoreMediaData && frame < frameCount {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary, &buffer)
        guard let buffer else { return }

        CVPixelBufferLockBaseAddress(buffer, [])
        if let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) {
            let t = Double(frame) / Double(frameCount)
            // Background sweeps through a gradient.
            let r = 0.08 + 0.35 * sin(t * 2 * .pi)
            let g = 0.10 + 0.25 * sin(t * 2 * .pi + 2)
            let b = 0.28 + 0.45 * sin(t * 2 * .pi + 4)
            context.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))

            // A bright disc sweeping left to right — clearly animated.
            let x = 80 + CGFloat(t) * CGFloat(width - 160)
            context.setFillColor(CGColor(red: 1, green: 0.92, blue: 0.35, alpha: 0.95))
            context.fillEllipse(in: CGRect(x: x - 90, y: 260, width: 180, height: 180))

            // Frame counter so a static screenshot is unambiguous.
            let text = "FRAME \(frame)  t=\(String(format: "%.2f", t))" as CFString
            let attrs: [CFString: Any] = [
                kCTFontAttributeName: CTFontCreateWithName("Helvetica-Bold" as CFString, 54, nil),
                kCTForegroundColorAttributeName: CGColor(red: 1, green: 1, blue: 1, alpha: 0.95),
            ]
            let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, text, attrs as CFDictionary)!)
            context.textPosition = CGPoint(x: 60, y: 120)
            CTLineDraw(line, context)
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
        frame += 1
    }

    // The writer must always be finished, otherwise the file has no `moov`
    // atom and cannot be opened.
    if frame >= frameCount && !finished {
        finished = true
        input.markAsFinished()
        writer.finishWriting { semaphore.signal() }
    }
}

semaphore.wait()
print("Wrote \(url.path)")
