#!/usr/bin/env swift
// Genera Resources/Centinela.icns desde código, no desde un archivo binario que nadie puede
// editar ni revisar en un diff. Se corre a mano cuando el ícono cambia:
//
//     swift Tools/generar-icono.swift
//
// Dibuja un escudo (el centinela) con un punto arriba, que es lo único que sobrevive a 16×16.
import AppKit
import CoreGraphics
import Foundation

func dibujar(lado: Int) -> CGImage {
    let ctx = CGContext(
        data: nil, width: lado, height: lado, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let l = CGFloat(lado)

    // Fondo: cuadrado redondeado con el radio proporcional que usa macOS (aprox. 22,5 %).
    let margen = l * 0.06
    let caja = CGRect(x: margen, y: margen, width: l - margen * 2, height: l - margen * 2)
    let fondo = CGPath(roundedRect: caja, cornerWidth: caja.width * 0.225, cornerHeight: caja.height * 0.225, transform: nil)
    ctx.addPath(fondo)
    ctx.clip()
    let degradado = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: [
            CGColor(red: 0.42, green: 0.29, blue: 0.75, alpha: 1),
            CGColor(red: 0.21, green: 0.14, blue: 0.45, alpha: 1),
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(degradado, start: CGPoint(x: 0, y: l), end: CGPoint(x: l, y: 0), options: [])
    ctx.resetClip()

    // Escudo: dos curvas que bajan a una punta. Trazo grueso para que se lea chico.
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

    // El punto: lo que queda visible a 16 píxeles.
    let r = l * 0.062
    ctx.setFillColor(CGColor(gray: 1, alpha: 0.95))
    ctx.fillEllipse(in: CGRect(x: cx - r, y: l * 0.50 - r, width: r * 2, height: r * 2))

    return ctx.makeImage()!
}

let salida = URL(fileURLWithPath: "Resources/Centinela.iconset")
try? FileManager.default.removeItem(at: salida)
try FileManager.default.createDirectory(at: salida, withIntermediateDirectories: true)

// Los nombres los define Apple; `iconutil` rechaza el iconset si falta alguno o si el nombre
// no calza exactamente con el tamaño.
for (base, escala) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let lado = base * escala
    let imagen = dibujar(lado: lado)
    let sufijo = escala == 1 ? "" : "@2x"
    let archivo = salida.appendingPathComponent("icon_\(base)x\(base)\(sufijo).png")
    let destino = CGImageDestinationCreateWithURL(archivo as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destino, imagen, nil)
    CGImageDestinationFinalize(destino)
}
print("iconset en \(salida.path). Ahora: iconutil -c icns \(salida.path)")
