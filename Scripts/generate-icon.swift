import AppKit

let canvas: CGFloat = 1024

func color(_ hex: UInt32) -> NSColor {
    NSColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

let gradientTop = color(0xFF9440)
let gradientBottom = color(0xEA6300)
let wedgeOrange = color(0xF36C00)
let handOrange = color(0xC85400)
let tickTint = color(0xF6D9BF)

let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

let squircle = NSBezierPath(
    roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824),
    xRadius: 184,
    yRadius: 184
)
NSGradient(starting: gradientTop, ending: gradientBottom)?.draw(in: squircle, angle: -90)

let center = NSPoint(x: 512, y: 478)
let faceRadius: CGFloat = 288

NSGraphicsContext.current?.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
shadow.shadowBlurRadius = 34
shadow.shadowOffset = NSSize(width: 0, height: -16)
shadow.set()

let watch = NSBezierPath()
watch.appendOval(in: NSRect(
    x: center.x - faceRadius,
    y: center.y - faceRadius,
    width: faceRadius * 2,
    height: faceRadius * 2
))
watch.append(NSBezierPath(
    roundedRect: NSRect(x: center.x - 62, y: center.y + faceRadius - 8, width: 124, height: 96),
    xRadius: 28,
    yRadius: 28
))
NSColor.white.setFill()
watch.fill()
NSGraphicsContext.current?.restoreGraphicsState()

let wedgeRadius: CGFloat = 226
let wedge = NSBezierPath()
wedge.move(to: center)
wedge.line(to: NSPoint(x: center.x, y: center.y + wedgeRadius))
wedge.appendArc(
    withCenter: center,
    radius: wedgeRadius,
    startAngle: 90,
    endAngle: -30,
    clockwise: true
)
wedge.close()
wedgeOrange.setFill()
wedge.fill()

tickTint.setStroke()
for angle in stride(from: 0.0, to: 360.0, by: 90.0) {
    let radians = angle * .pi / 180
    let tick = NSBezierPath()
    tick.lineWidth = 20
    tick.lineCapStyle = .round
    tick.move(to: NSPoint(
        x: center.x + cos(radians) * 244,
        y: center.y + sin(radians) * 244
    ))
    tick.line(to: NSPoint(
        x: center.x + cos(radians) * 266,
        y: center.y + sin(radians) * 266
    ))
    tick.stroke()
}

let handAngle = -30.0 * .pi / 180
let hand = NSBezierPath()
hand.lineWidth = 34
hand.lineCapStyle = .round
hand.move(to: center)
hand.line(to: NSPoint(
    x: center.x + cos(handAngle) * 238,
    y: center.y + sin(handAngle) * 238
))
handOrange.setStroke()
hand.stroke()

handOrange.setFill()
NSBezierPath(ovalIn: NSRect(x: center.x - 34, y: center.y - 34, width: 68, height: 68)).fill()

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let rep = NSBitmapImageRep(data: tiff),
    let png = rep.representation(using: .png, properties: [:])
else {
    fatalError("Failed to render icon")
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try png.write(to: output)
print("Wrote \(output.path)")
