import AppKit

enum RenderError: Error {
    case imageCreation
}

let rgb = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 255) / 255,
        green: CGFloat((hex >> 8) & 255) / 255,
        blue: CGFloat(hex & 255) / 255,
        alpha: alpha
    )
}

func render(size: Int) throws -> Data {
    guard let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
        space: rgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw RenderError.imageCreation
    }

    let scale = CGFloat(size) / 1024
    context.scaleBy(x: scale, y: scale)
    let tile = CGPath(roundedRect: CGRect(x: 91, y: 97, width: 842, height: 842),
                      cornerWidth: 194, cornerHeight: 194, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -24), blur: 35, color: color(0x081E25, alpha: 0.38))
    context.setFillColor(color(0x102731))
    context.addPath(tile)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tile)
    context.clip()
    if let gradient = CGGradient(
        colorsSpace: rgb, colors: [color(0x375A61), color(0x182F39), color(0x0D1D28)] as CFArray,
        locations: [0, 0.50, 1]
    ) {
        context.drawLinearGradient(
            gradient, start: CGPoint(x: 200, y: 925), end: CGPoint(x: 838, y: 110),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }
    let glowCenter = CGPoint(x: 357, y: 715)
    if let glow = CGGradient(
        colorsSpace: rgb, colors: [color(0x76F1CB, alpha: 0.25), color(0x76F1CB, alpha: 0)] as CFArray,
        locations: [0, 1]
    ) {
        context.drawRadialGradient(glow, startCenter: glowCenter, startRadius: 0,
                                   endCenter: glowCenter, endRadius: 575, options: [])
    }

    context.setStrokeColor(color(0x97DBD0, alpha: 0.17))
    context.setLineWidth(5)
    for radius in [CGFloat(242), 305] {
        context.strokeEllipse(in: CGRect(x: 512 - radius, y: 533 - radius, width: 2 * radius, height: 2 * radius))
    }
    context.setStrokeColor(color(0xD9FFF4, alpha: 0.30))
    context.setLineWidth(4)
    context.addPath(tile)
    context.strokePath()
    context.restoreGState()

    let mouse = CGPath(roundedRect: CGRect(x: 337, y: 279, width: 350, height: 487),
                       cornerWidth: 151, cornerHeight: 151, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -16), blur: 37, color: color(0x07141A, alpha: 0.55))
    context.setFillColor(color(0xBDEDE1))
    context.addPath(mouse)
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.addPath(mouse)
    context.clip()
    if let shell = CGGradient(
        colorsSpace: rgb, colors: [color(0xF3FFF9), color(0xBCE9DE), color(0x76B8AF)] as CFArray,
        locations: [0, 0.54, 1]
    ) {
        context.drawLinearGradient(shell, start: CGPoint(x: 389, y: 747), end: CGPoint(x: 647, y: 283),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
    context.setFillColor(color(0x75E4BF))
    context.fill(CGRect(x: 337, y: 555, width: 175, height: 211))
    context.setStrokeColor(color(0x17393D, alpha: 0.77))
    context.setLineWidth(13)
    context.move(to: CGPoint(x: 512, y: 771))
    context.addLine(to: CGPoint(x: 512, y: 555))
    context.move(to: CGPoint(x: 337, y: 555))
    context.addLine(to: CGPoint(x: 687, y: 555))
    context.strokePath()
    context.restoreGState()

    context.setStrokeColor(color(0xF0FFF6, alpha: 0.66))
    context.setLineWidth(6)
    context.addPath(mouse)
    context.strokePath()

    let wheel = CGPath(roundedRect: CGRect(x: 488, y: 601, width: 48, height: 86),
                       cornerWidth: 24, cornerHeight: 24, transform: nil)
    context.setFillColor(color(0x193940))
    context.addPath(wheel)
    context.fillPath()
    context.setStrokeColor(color(0xABEAD8))
    context.setLineWidth(5)
    context.setLineCap(.round)
    for y in [CGFloat(632), 644, 656] {
        context.move(to: CGPoint(x: 504, y: y))
        context.addLine(to: CGPoint(x: 520, y: y))
    }
    context.strokePath()

    guard let image = context.makeImage(),
          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    else {
        throw RenderError.imageCreation
    }
    return png
}

func appendLength(_ length: Int, to data: inout Data) {
    var encoded = UInt32(length).bigEndian
    withUnsafeBytes(of: &encoded) { data.append(contentsOf: $0) }
}

let renderings = [
    ("icp4", 16), ("ic11", 32), ("icp5", 32), ("ic12", 64),
    ("ic07", 128), ("ic13", 256), ("ic08", 256), ("ic14", 512),
    ("ic09", 512), ("ic10", 1024),
]
var elements = Data()
for (type, size) in renderings {
    let png = try render(size: size)
    elements.append(contentsOf: type.utf8)
    appendLength(png.count + 8, to: &elements)
    elements.append(png)
}

var icon = Data("icns".utf8)
appendLength(elements.count + 8, to: &icon)
icon.append(elements)
try icon.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
