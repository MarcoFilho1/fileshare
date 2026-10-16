// Desenha o ícone do FileShare e gera Resources/AppIcon.icns.
// Uso: swift scripts/make-icon.swift  (rodar em mac/FileShare; precisa do iconutil do macOS)
//
// Squircle azul na grade padrão do macOS (824 de 1024, cantos contínuos), com as duas setas ⇄
// do ícone da barra de menu. O Android usa a mesma geometria (res/drawable/ic_launcher_*.xml).
import AppKit

/// Retângulo de cantos contínuos, como os ícones da Apple: cada canto é um quarto de superelipse
/// (|x|^n + |y|^n = 1), que sai das laterais sem quebra de curvatura.
func squircle(_ r: CGRect, corner c: CGFloat = 270, exponent n: CGFloat = 3.4) -> CGPath {
    let path = CGMutablePath()
    let centers = [
        CGPoint(x: r.maxX - c, y: r.maxY - c), CGPoint(x: r.minX + c, y: r.maxY - c),
        CGPoint(x: r.minX + c, y: r.minY + c), CGPoint(x: r.maxX - c, y: r.minY + c),
    ]
    for (i, center) in centers.enumerated() {
        for step in 0...60 {
            let t = (CGFloat(i) + CGFloat(step) / 60) * .pi / 2
            let cx = cos(t), sy = sin(t)
            let p = CGPoint(x: center.x + c * copysign(pow(abs(cx), 2 / n), cx),
                            y: center.y + c * copysign(pow(abs(sy), 2 / n), sy))
            i == 0 && step == 0 ? path.move(to: p) : path.addLine(to: p)
        }
    }
    path.closeSubpath()
    return path
}

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = size / 1024
    ctx.scaleBy(x: s, y: s)

    // sombra do próprio ícone, como os do sistema
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squircle(body)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: NSColor.black.withAlphaComponent(0.28).cgColor)
    ctx.addPath(shape)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // fundo: do azul claro ao azul profundo, sem roxo
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let gradient = CGGradient(colorsSpace: space, colors: [
        CGColor(srgbRed: 0.27, green: 0.66, blue: 1.00, alpha: 1),
        CGColor(srgbRed: 0.13, green: 0.40, blue: 0.96, alpha: 1),
        CGColor(srgbRed: 0.09, green: 0.28, blue: 0.77, alpha: 1), // azul profundo (sem violeta)
    ] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 260, y: 924), end: CGPoint(x: 764, y: 100),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    // brilho de vidro no alto
    let gloss = CGGradient(colorsSpace: space, colors: [
        CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.22),
        CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gloss, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 560), options: [])
    ctx.restoreGState()

    // borda clara fina, como a borda de vidro dos ícones do macOS 26
    ctx.saveGState()
    ctx.addPath(squircle(body.insetBy(dx: 2, dy: 2)))
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.28).cgColor)
    ctx.setLineWidth(4)
    ctx.strokePath()
    ctx.restoreGState()

    // setas ⇄: de cima para a direita, de baixo para a esquerda
    func arrow(from a: CGPoint, to b: CGPoint, alpha: CGFloat) {
        let dir: CGFloat = b.x > a.x ? 1 : -1
        let path = CGMutablePath()
        path.move(to: a)
        path.addLine(to: b)
        path.move(to: CGPoint(x: b.x - dir * 90, y: b.y + 90))
        path.addLine(to: b)
        path.addLine(to: CGPoint(x: b.x - dir * 90, y: b.y - 90))
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: NSColor(srgbRed: 0.05, green: 0.12, blue: 0.45, alpha: 0.45).cgColor)
        ctx.addPath(path)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(alpha).cgColor)
        ctx.setLineWidth(62)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.strokePath()
        ctx.restoreGState()
    }
    arrow(from: CGPoint(x: 318, y: 624), to: CGPoint(x: 706, y: 624), alpha: 1)
    arrow(from: CGPoint(x: 706, y: 400), to: CGPoint(x: 318, y: 400), alpha: 0.82)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let png = drawIcon(size: CGFloat(base * scale)).representation(using: .png, properties: [:])!
        try png.write(to: iconset.appendingPathComponent(name))
    }
}
try fm.createDirectory(atPath: "Resources", withIntermediateDirectories: true)
let preview = drawIcon(size: 1024).representation(using: .png, properties: [:])!
try preview.write(to: URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "\(NSTemporaryDirectory())AppIcon-1024.png"))
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "Resources/AppIcon.icns" : "iconutil falhou")
