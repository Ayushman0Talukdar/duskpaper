// Captures the pixels of every duskpaper desktop-level wallpaper window twice and
// reports how much each one changed, which proves whether each display is
// actually playing.
import CoreGraphics
import Foundation

func wallpaperWindows() -> [(CGWindowID, CGRect)] {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    var result: [(CGWindowID, CGRect)] = []
    for w in list {
        let owner = w["kCGWindowOwnerName"] as? String ?? ""
        let layer = w["kCGWindowLayer"] as? Int ?? 0
        guard owner == "duskpaper", layer < -1000 else { continue }
        let number = w["kCGWindowNumber"] as? CGWindowID ?? 0
        var bounds = CGRect.zero
        if let b = w["kCGWindowBounds"] as? [String: Any],
           let x = b["X"] as? Double, let y = b["Y"] as? Double,
           let ww = b["Width"] as? Double, let hh = b["Height"] as? Double {
            bounds = CGRect(x: x, y: y, width: ww, height: hh)
        }
        result.append((number, bounds))
    }
    return result
}

func capture(_ id: CGWindowID) -> CGImage? {
    CGWindowListCreateImage(
        .infinite,
        .optionIncludingWindow,
        id,
        [.boundsIgnoreFraming, .bestResolution]
    )
}

func rawBytes(_ image: CGImage) -> (width: Int, height: Int, pixels: [UInt8])? {
    let width = image.width, height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let info = CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    guard let ctx = pixels.withUnsafeMutableBytes({ raw -> CGContext? in
        CGContext(
            data: raw.baseAddress,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace, bitmapInfo: info
        )
    }) else { return nil }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return (width, height, pixels)
}

func meanAbsDiff(_ a: (width: Int, height: Int, pixels: [UInt8])?,
                 _ b: (width: Int, height: Int, pixels: [UInt8])?) -> Double {
    guard let a, let b else { return -1 }
    let w = min(a.width, b.width), h = min(a.height, b.height)
    var total = 0.0
    var count = 0
    for y in stride(from: 0, to: h, by: 32) {
        for x in stride(from: 0, to: w, by: 32) {
            let ia = (y * a.width + x) * 4
            let ib = (y * b.width + x) * 4
            total += abs(Double(a.pixels[ia]) - Double(b.pixels[ib]))
                + abs(Double(a.pixels[ia + 1]) - Double(b.pixels[ib + 1]))
                + abs(Double(a.pixels[ia + 2]) - Double(b.pixels[ib + 2]))
            count += 3
        }
    }
    return count > 0 ? total / Double(count) : 0
}

let windows = wallpaperWindows()
print("duskpaper wallpaper windows on screen: \(windows.count)")
guard !windows.isEmpty else {
    print("RESULT: NO WALLPAPER WINDOWS FOUND")
    exit(1)
}

var firsts: [(CGWindowID, CGRect, (width: Int, height: Int, pixels: [UInt8])?)] = []
for w in windows {
    firsts.append((w.0, w.1, capture(w.0).flatMap(rawBytes)))
}

Thread.sleep(forTimeInterval: 2.0)

var allPlaying = true
for (id, bounds, first) in firsts {
    let second = capture(id).flatMap(rawBytes)
    let diff = meanAbsDiff(first, second)
    let playing = diff > 0.5
    if !playing { allPlaying = false }
    print("  window \(id) bounds=\(bounds) diff=\(String(format: "%.3f", diff)) -> \(playing ? "PLAYING" : "STUCK")")
}
print(allPlaying ? "RESULT: ALL DISPLAYS PLAYING" : "RESULT: AT LEAST ONE DISPLAY STUCK")
