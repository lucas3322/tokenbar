import AppKit
import CoreGraphics
import Foundation

/// Gera o ícone do app por código, para sair nítido em todos os tamanhos.
/// O desenho ecoa o painel: dois anéis concêntricos, um por ferramenta.

/// Squircle da Apple (superelipse), não um retângulo de cantos arredondados.
func squircle(in rect: CGRect, n: Double = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY
    let steps = 720
    for i in 0...steps {
        let t = Double(i) / Double(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = cx + a * (ct < 0 ? -1 : 1) * pow(abs(ct), 2 / n)
        let y = cy + b * (st < 0 ? -1 : 1) * pow(abs(st), 2 / n)
        i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

func arc(_ ctx: CGContext, center: CGPoint, radius: CGFloat, width: CGFloat,
         startDeg: Double, sweepDeg: Double, colors: [CGColor]) {
    ctx.saveGState()
    let path = CGMutablePath()
    path.addArc(center: center, radius: radius,
                startAngle: CGFloat(startDeg * .pi / 180),
                endAngle: CGFloat((startDeg + sweepDeg) * .pi / 180),
                clockwise: sweepDeg < 0)
    ctx.addPath(path)
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    // Gradiente ao longo do anel dá profundidade sem poluir em tamanhos pequenos.
    let space = CGColorSpaceCreateDeviceRGB()
    if let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: [0, 1]) {
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: center.x - radius, y: center.y + radius),
                               end: CGPoint(x: center.x + radius, y: center.y - radius),
                               options: [])
    }
    ctx.restoreGState()
}

func render(size: CGFloat) -> Data {
    let scale: CGFloat = 1
    let px = Int(size * scale)
    let space = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8,
                              bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fatalError("contexto gráfico")
    }
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    let full = CGRect(x: 0, y: 0, width: size, height: size)
    // A arte ocupa ~92% do quadro, como manda o guia de ícones da Apple.
    let inset = size * 0.04
    let body = full.insetBy(dx: inset, dy: inset)

    // Fundo grafite com leve gradiente vertical.
    ctx.saveGState()
    ctx.addPath(squircle(in: body))
    ctx.clip()
    let bg = CGGradient(colorsSpace: space, colors: [
        CGColor(red: 0.20, green: 0.22, blue: 0.27, alpha: 1),
        CGColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: body.maxY),
                           end: CGPoint(x: 0, y: body.minY), options: [])

    // Brilho superior, para não ficar chapado.
    let sheen = CGGradient(colorsSpace: space, colors: [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.14),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 0, y: body.maxY),
                           end: CGPoint(x: 0, y: body.midY), options: [])
    ctx.restoreGState()

    let center = CGPoint(x: full.midX, y: full.midY)

    // Trilhos apagados sob cada anel.
    let track = CGColor(red: 1, green: 1, blue: 1, alpha: 0.07)
    arc(ctx, center: center, radius: size * 0.30, width: size * 0.085,
        startDeg: 90, sweepDeg: -360, colors: [track, track])
    arc(ctx, center: center, radius: size * 0.175, width: size * 0.075,
        startDeg: 90, sweepDeg: -360, colors: [track, track])

    // Anel externo: Claude (verde). Anel interno: Codex (azul).
    arc(ctx, center: center, radius: size * 0.30, width: size * 0.085,
        startDeg: 90, sweepDeg: -252,
        colors: [CGColor(red: 0.31, green: 0.85, blue: 0.56, alpha: 1),
                 CGColor(red: 0.18, green: 0.70, blue: 0.45, alpha: 1)])
    arc(ctx, center: center, radius: size * 0.175, width: size * 0.075,
        startDeg: 90, sweepDeg: -140,
        colors: [CGColor(red: 0.47, green: 0.67, blue: 1.00, alpha: 1),
                 CGColor(red: 0.29, green: 0.48, blue: 0.95, alpha: 1)])

    // Núcleo claro: dá um ponto focal que sobrevive a 16px.
    ctx.setFillColor(CGColor(red: 0.96, green: 0.97, blue: 1.0, alpha: 0.95))
    let core = size * 0.052
    ctx.fillEllipse(in: CGRect(x: center.x - core, y: center.y - core, width: core * 2, height: core * 2))

    guard let image = ctx.makeImage() else { fatalError("imagem") }
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: px, height: px)
    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
    return data
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// Nomes exigidos pelo iconutil.
let variants: [(String, CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, size) in variants {
    try! render(size: size).write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
}
print("✓ \(variants.count) tamanhos em \(outDir)")
