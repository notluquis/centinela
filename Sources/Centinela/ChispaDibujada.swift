import AppKit
import CentinelaCore

// El dibujo vive acá y no junto a la aritmética a propósito: `CentinelaCore` no importa AppKit,
// y esa es la razón por la que su suite corre en un runner sin sesión gráfica. `Chispa.normalizar`
// sí tiene tests; esto es sólo trazar los puntos que aquélla devuelve.
extension Chispa {
    /// Dibuja la chispa como imagen de plantilla, para la etiqueta de la barra de menús.
    ///
    /// Es de plantilla (`isTemplate`) a propósito: en la barra de macOS 26 y 27 el fondo es
    /// transparente y encima va el papel tapiz, así que el color lo decide el sistema, que sabe
    /// si está en claro o en oscuro. Un color propio deja de contrastar según el escritorio.
    static func imagen(_ valores: [Int], ancho: CGFloat = 26, alto: CGFloat = 11) -> NSImage? {
        let puntos = normalizar(valores)
        guard puntos.count > 1 else { return nil }

        let imagen = NSImage(size: NSSize(width: ancho, height: alto), flipped: false) { _ in
            let trazo = NSBezierPath()
            trazo.lineWidth = 1.2
            trazo.lineCapStyle = .round
            trazo.lineJoinStyle = .round
            // Un píxel de margen arriba y abajo: con grosor 1,2 el máximo y el mínimo quedarían
            // cortados por el borde de la imagen.
            let margen: CGFloat = 1
            for (indice, punto) in puntos.enumerated() {
                let sitio = NSPoint(x: punto.x * ancho, y: margen + punto.y * (alto - margen * 2))
                if indice == 0 { trazo.move(to: sitio) } else { trazo.line(to: sitio) }
            }
            NSColor.black.setStroke()
            trazo.stroke()
            return true
        }
        imagen.isTemplate = true
        return imagen
    }
}
