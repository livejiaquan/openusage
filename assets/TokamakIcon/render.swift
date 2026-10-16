import AppKit
// usage: render <size> <out.png> — draws the Tokamak app icon (macOS icon grid: 824/1024 body, 100 px margin).
let size = CGFloat(Double(CommandLine.arguments[1])!)
let out = CommandLine.arguments[2]
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let s = size / 1024
let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
let squircle = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)
NSGradient(colors: [NSColor(srgbRed: 0.07, green: 0.05, blue: 0.20, alpha: 1),
                    NSColor(srgbRed: 0.23, green: 0.10, blue: 0.42, alpha: 1)])!.draw(in: squircle, angle: 90)
// Map the 24-unit mark space (y down) into the body with a margin.
let unit = body.width * 0.78 / 24
let ox = body.midX - 12 * unit, oy = body.midY + 12 * unit
func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: ox + x * unit, y: oy - y * unit) }
func oval(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> NSRect {
    NSRect(x: ox + (cx - rx) * unit, y: oy - (cy + ry) * unit, width: 2 * rx * unit, height: 2 * ry * unit)
}
// Soft plasma glow behind the ring.
let glow = NSBezierPath(ovalIn: oval(11, 14.2, 11.2, 7))
NSColor(srgbRed: 1, green: 0.35, blue: 0.75, alpha: 0.18).setFill(); glow.fill()
let ring = NSBezierPath(ovalIn: oval(11, 14.2, 9.6, 5.6))
ring.append(NSBezierPath(ovalIn: oval(11, 13.4, 4.4, 1.9)))
ring.windingRule = .evenOdd
NSGradient(colors: [NSColor(srgbRed: 1.0, green: 0.30, blue: 0.80, alpha: 1),
                    NSColor(srgbRed: 1.0, green: 0.71, blue: 0.28, alpha: 1)])!.draw(in: ring, angle: 0)
let spark = NSBezierPath()
let (cx, cy, r, w): (CGFloat, CGFloat, CGFloat, CGFloat) = (19.4, 4.6, 3.6, 0.55)
spark.move(to: p(cx, cy - r))
spark.curve(to: p(cx + r, cy), controlPoint1: p(cx + w, cy - w), controlPoint2: p(cx + w, cy - w))
spark.curve(to: p(cx, cy + r), controlPoint1: p(cx + w, cy + w), controlPoint2: p(cx + w, cy + w))
spark.curve(to: p(cx - r, cy), controlPoint1: p(cx - w, cy + w), controlPoint2: p(cx - w, cy + w))
spark.curve(to: p(cx, cy - r), controlPoint1: p(cx - w, cy - w), controlPoint2: p(cx - w, cy - w))
spark.close()
NSColor.white.setFill(); spark.fill()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
