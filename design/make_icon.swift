import AppKit
import CoreGraphics

let size = 1024
let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/AppIcon-1024.png"

guard let ctx = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fatalError("could not create context")
}

let rect = CGRect(x: 0, y: 0, width: size, height: size)

// Background: rounded-square, warm tan (#D4A27F), original artwork, no Claude
// logo/mascot. Subtle gradient (lighter center, slightly deeper edge) for warmth.
let cornerRadius = CGFloat(size) * 0.225
let bgPath = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
ctx.addPath(bgPath)
ctx.clip()

func rgb(_ hex: (Int, Int, Int)) -> CGColor {
    CGColor(red: CGFloat(hex.0) / 255, green: CGFloat(hex.1) / 255, blue: CGFloat(hex.2) / 255, alpha: 1.0)
}

let base = (0xD4, 0xA2, 0x7F) // #D4A27F
let lighter = (min(base.0 + 14, 255), min(base.1 + 12, 255), min(base.2 + 10, 255))
let deeper = (max(base.0 - 24, 0), max(base.1 - 24, 0), max(base.2 - 22, 0))

let colors = [rgb(lighter), rgb(base), rgb(deeper)] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 0.55, 1.0])!
ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: size),
    end: CGPoint(x: size, y: 0),
    options: []
)

// Foreground glyph: a dot with three hand-drawn (wobbly, imperfect) radio-wave
// arcs, deep coffee-brown ink on the tan background. Wobble is a deterministic
// sine perturbation of the radius, not randomness, so regenerating gives the same
// result every time.
let center = CGPoint(x: CGFloat(size) * 0.40, y: CGFloat(size) * 0.50)
let inkColor = rgb((0x3A, 0x28, 0x1C))

func wobbledPoints(radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, amplitude: CGFloat, frequency: CGFloat, phase: CGFloat, segments: Int) -> [CGPoint] {
    (0...segments).map { i in
        let t = CGFloat(i) / CGFloat(segments)
        let angle = startAngle + (endAngle - startAngle) * t
        let wobble = sin(t * .pi * frequency + phase) * amplitude
            + sin(t * .pi * frequency * 2.3 + phase * 1.7) * (amplitude * 0.35)
        let r = radius + wobble
        return CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
    }
}

func strokeSketchyPath(points: [CGPoint], width: CGFloat, alpha: CGFloat, passes: Int) {
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    for pass in 0..<passes {
        let offset = CGFloat(pass) * 1.6 - CGFloat(passes - 1) * 0.8
        ctx.setStrokeColor(inkColor.copy(alpha: alpha / CGFloat(passes) * 1.6) ?? inkColor)
        ctx.setLineWidth(width)
        ctx.beginPath()
        for (i, p) in points.enumerated() {
            let jittered = CGPoint(x: p.x + offset, y: p.y + offset * 0.4)
            if i == 0 {
                ctx.move(to: jittered)
            } else {
                ctx.addLine(to: jittered)
            }
        }
        ctx.strokePath()
    }
}

// Dot: slightly irregular circle, not a perfect one.
let dotRadius = CGFloat(size) * 0.052
let dotPoints = wobbledPoints(radius: dotRadius, startAngle: 0, endAngle: .pi * 2, amplitude: dotRadius * 0.08, frequency: 5, phase: 0.6, segments: 60)
ctx.setFillColor(inkColor)
ctx.beginPath()
for (i, p) in dotPoints.enumerated() {
    if i == 0 { ctx.move(to: p) } else { ctx.addLine(to: p) }
}
ctx.closePath()
ctx.fillPath()

// Three concentric hand-sketched wave arcs, each with its own wobble phase so
// they don't look mechanically repeated.
let sweep = CGFloat.pi * 0.62
let arcs: [(radius: CGFloat, width: CGFloat, alpha: CGFloat, amp: CGFloat, phase: CGFloat)] = [
    (CGFloat(size) * 0.155, CGFloat(size) * 0.024, 1.0, CGFloat(size) * 0.006, 0.3),
    (CGFloat(size) * 0.235, CGFloat(size) * 0.020, 0.82, CGFloat(size) * 0.009, 1.1),
    (CGFloat(size) * 0.315, CGFloat(size) * 0.017, 0.66, CGFloat(size) * 0.012, 2.0),
]

for arc in arcs {
    let points = wobbledPoints(radius: arc.radius, startAngle: -sweep / 2, endAngle: sweep / 2, amplitude: arc.amp, frequency: 3, phase: arc.phase, segments: 48)
    strokeSketchyPath(points: points, width: arc.width, alpha: arc.alpha, passes: 2)
}

guard let cgImage = ctx.makeImage() else {
    fatalError("could not make image")
}

let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
    fatalError("could not encode png")
}

try! pngData.write(to: URL(fileURLWithPath: outputPath))
print("wrote \(outputPath)")
