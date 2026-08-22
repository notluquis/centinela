#!/usr/bin/env swift
// Generates Resources/Centinela.icns from code, not from a binary file nobody can edit or
// review in a diff. Run by hand when the icon changes:
//
//     swift Tools/generate-icon.swift
//
// Draws a shield (the sentinel) with a dot on it, which is all that survives at 16×16.
import AppKit
import CoreGraphics
import Foundation

func draw(side: Int) -> CGImage {
    let ctx = CGContext(
        data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let l = CGFloat(side)

    // Background: rounded square with the proportional radius macOS uses (about 22.5%).
    let margen = l * 0.06
    let caja = CGRect(x: margen, y: margen, width: l - margen * 2, height: l - margen * 2)
    let fondo = CGPath(roundedRect: caja, cornerWidth: caja.width * 0.225, cornerHeight: caja.height * 0.225, transform: nil)
    ctx.addPath(fondo)
    ctx.clip()
    let degradado = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: [
            CGColor(red: 0.42, green: 0.29, blue: 0.75, alpha: 1),
            CGColor(red: 0.21, green: 0.14, blue: 0.45, alpha: 1)
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(degradado, start: CGPoint(x: 0, y: l), end: CGPoint(x: l, y: 0), options: [])
    ctx.resetClip()

    // Shield: two curves meeting at a point. Thick stroke so it reads small.
    let cx = l / 2, top = l * 0.74, bottom = l * 0.24, ancho = l * 0.19
    let escudo = CGMutablePath()
    escudo.move(to: CGPoint(x: cx - ancho, y: top))
    escudo.addLine(to: CGPoint(x: cx + ancho, y: top))
    escudo.addCurve(
        to: CGPoint(x: cx, y: bottom),
        control1: CGPoint(x: cx + ancho, y: top - l * 0.22),
        control2: CGPoint(x: cx + ancho * 0.7, y: bottom + l * 0.06)
    )
    escudo.addCurve(
        to: CGPoint(x: cx - ancho, y: top),
        control1: CGPoint(x: cx - ancho * 0.7, y: bottom + l * 0.06),
        control2: CGPoint(x: cx - ancho, y: top - l * 0.22)
    )
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.95))
    ctx.setLineWidth(max(1, l * 0.055))
    ctx.setLineJoin(.round)
    ctx.addPath(escudo)
    ctx.strokePath()

    // The dot: what stays visible at 16 pixels.
    let r = l * 0.062
    ctx.setFillColor(CGColor(gray: 1, alpha: 0.95))
    ctx.fillEllipse(in: CGRect(x: cx - r, y: l * 0.50 - r, width: r * 2, height: r * 2))

    return ctx.makeImage()!
}

let output = URL(fileURLWithPath: "Resources/Centinela.iconset")
try? FileManager.default.removeItem(at: output)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

// Apple defines the names; `iconutil` rejects the iconset if one is missing or if the name
// does not match the size exactly.
for (base, escala) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let lado = base * escala
    let imagen = draw(side: lado)
    let sufijo = escala == 1 ? "" : "@2x"
    let archivo = output.appendingPathComponent("icon_\(base)x\(base)\(sufijo).png")
    let destino = CGImageDestinationCreateWithURL(archivo as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destino, imagen, nil)
    CGImageDestinationFinalize(destino)
}
print("iconset at \(output.path). Next: iconutil -c icns \(output.path)")
