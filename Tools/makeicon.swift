// Generates the duskpaper app icon as a set of PNGs, then packages them into
// an .iconset folder. Run with:  swift Tools/makeicon.swift Resources
//
// The design is a sunset over layered purple hills, ported from the original
// 1024px design mockup (rounded square, vertical sky gradient, stars, sun with
// glow, three hill layers, top gloss and a subtle edge highlight).
import AppKit
import CoreGraphics
import Foundation

extension CGColor {
    /// An sRGB colour from a `0xRRGGBB` literal, matching the design mockup's
    /// CSS colours directly.
    static func design(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

let outputDirectory = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources"
let iconset = URL(fileURLWithPath: outputDirectory).appendingPathComponent("AppIcon.iconset")

try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

/// Converts a y-coordinate from the design's top-down space to CoreGraphics'
/// bottom-up space. All constant coordinates below are written in the design
/// space so they can be compared against the mockup directly.
func y(_ value: CGFloat) -> CGFloat { 1024 - value }

func drawIcon(size: CGFloat) -> CGImage? {
    let pixels = Int(size)
    guard let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    context.clear(CGRect(x: 0, y: 0, width: size, height: size))
    context.scaleBy(x: size / 1024, y: size / 1024)

    let rgb = CGColorSpaceCreateDeviceRGB()

    // Rounded-square body, clipped so every layer stays inside it.
    let inset: CGFloat = 100
    let body = CGRect(x: inset, y: inset, width: 1024 - inset * 2, height: 1024 - inset * 2)
    let radius: CGFloat = 186
    let shape = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    context.saveGState()
    context.addPath(shape)
    context.clip()

    // Sky: dark indigo at the top through violet and pink to a warm orange
    // horizon.
    let sky = CGGradient(
        colorsSpace: rgb,
        colors: [
            CGColor.design(0x1E1B4B),
            CGColor.design(0x6D28D9),
            CGColor.design(0xF472B6),
            CGColor.design(0xFDBA74),
        ] as CFArray,
        locations: [0, 0.4, 0.7, 1]
    )
    if let sky {
        context.drawLinearGradient(
            sky,
            start: CGPoint(x: 512, y: y(100)),
            end: CGPoint(x: 512, y: y(924)),
            options: []
        )
    }

    // A few stars in the dark upper sky.
    context.setFillColor(CGColor(gray: 1, alpha: 0.85))
    for star in [
        (x: CGFloat(260), y: y(230), r: CGFloat(5)),
        (x: CGFloat(390), y: y(320), r: CGFloat(3.5)),
        (x: CGFloat(640), y: y(215), r: CGFloat(4.5)),
        (x: CGFloat(760), y: y(330), r: CGFloat(3.5)),
        (x: CGFloat(560), y: y(290), r: CGFloat(3)),
        (x: CGFloat(200), y: y(390), r: CGFloat(3)),
    ] {
        context.fillEllipse(in: CGRect(
            x: star.x - star.r,
            y: star.y - star.r,
            width: star.r * 2,
            height: star.r * 2
        ))
    }

    // Sun with a soft warm glow behind it.
    let glow = CGGradient(
        colorsSpace: rgb,
        colors: [
            CGColor.design(0xFEF3C7, alpha: 0.9),
            CGColor.design(0xFEF3C7, alpha: 0),
        ] as CFArray,
        locations: [0, 1]
    )
    if let glow {
        context.drawRadialGradient(
            glow,
            startCenter: CGPoint(x: 512, y: y(590)),
            startRadius: 0,
            endCenter: CGPoint(x: 512, y: y(590)),
            endRadius: 260,
            options: [.drawsAfterEndLocation]
        )
    }
    context.setFillColor(CGColor.design(0xFEF3C7))
    context.fillEllipse(in: CGRect(x: 512 - 132, y: y(590) - 132, width: 264, height: 264))

    // Hill layers, back to front. Each path is the design's path mirrored
    // into CoreGraphics space, closed along the bottom edge of the icon.
    let hills: [(color: CGColor, path: [(CGPoint, CGPoint, CGPoint)])] = [
        // Back layer (violet, slightly translucent).
        (
            CGColor.design(0x7C3AED, alpha: 0.85),
            [
                ((CGPoint(x: 240, y: 454)), (CGPoint(x: 350, y: 414)), (CGPoint(x: 470, y: 474))),
                ((CGPoint(x: 590, y: 534)), (CGPoint(x: 700, y: 534)), (CGPoint(x: 924, y: 414))),
            ]
        ),
        // Middle layer (deep violet).
        (
            CGColor.design(0x5B21B6),
            [
                ((CGPoint(x: 230, y: 364)), (CGPoint(x: 380, y: 314)), (CGPoint(x: 520, y: 374))),
                ((CGPoint(x: 660, y: 434)), (CGPoint(x: 780, y: 394)), (CGPoint(x: 924, y: 314))),
            ]
        ),
        // Front layer (near-black indigo).
        (
            CGColor.design(0x2E1065),
            [
                ((CGPoint(x: 260, y: 274)), (CGPoint(x: 420, y: 224)), (CGPoint(x: 580, y: 274))),
                ((CGPoint(x: 740, y: 324)), (CGPoint(x: 820, y: 284)), (CGPoint(x: 924, y: 224))),
            ]
        ),
    ]

    for hill in hills {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 100, y: y(924)))
        for segment in hill.path {
            path.addCurve(
                to: CGPoint(x: segment.2.x, y: segment.2.y),
                control1: CGPoint(x: segment.0.x, y: segment.0.y),
                control2: CGPoint(x: segment.1.x, y: segment.1.y)
            )
        }
        path.addLine(to: CGPoint(x: 924, y: y(924)))
        path.closeSubpath()
        context.addPath(path)
        context.setFillColor(hill.color)
        context.fillPath()
    }

    // Gloss on the top edge, fading out a third of the way down.
    let gloss = CGGradient(
        colorsSpace: rgb,
        colors: [
            CGColor(gray: 1, alpha: 0.22),
            CGColor(gray: 1, alpha: 0),
        ] as CFArray,
        locations: [0, 1]
    )
    if let gloss {
        context.drawLinearGradient(
            gloss,
            start: CGPoint(x: 512, y: y(100)),
            end: CGPoint(x: 512, y: y(388)),
            options: []
        )
    }

    context.restoreGState()

    // Subtle inner border for definition on light backgrounds.
    context.addPath(shape)
    context.setStrokeColor(CGColor(gray: 1, alpha: 0.25))
    context.setLineWidth(3)
    context.strokePath()

    return context.makeImage()
}

func writePNG(_ image: CGImage, to url: URL) {
    guard let data = image.dataProvider?.data,
          let _ = CGImageSourceCreateWithData(data as CFData, nil),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
    else { return }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

let variants: [(name: String, points: CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for variant in variants {
    guard let image = drawIcon(size: variant.points) else { continue }
    writePNG(image, to: iconset.appendingPathComponent(variant.name))
}

print("Icon set written to \(iconset.path)")
