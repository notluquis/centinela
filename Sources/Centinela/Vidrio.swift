import SwiftUI

/// Liquid Glass, el material que macOS 26 introdujo, sólo donde suma y sólo donde existe.
///
/// Dos decisiones que conviene dejar escritas:
///
/// 1. **El fondo del panel no se toca.** `MenuBarExtra(.window)` ya lo dibuja con el material
///    del sistema. Ponerle `.glassEffect()` encima apila dos materiales y el resultado se ve
///    turbio, no vidrioso.
/// 2. **Los controles del pie sí.** Son botones sueltos sobre ese material, que es exactamente
///    el caso para el que `.buttonStyle(.glass)` existe.
///
/// El objetivo de despliegue es macOS 14, así que todo va detrás de `#available`: en 14 y 15 se
/// cae al estilo plano de siempre, que es correcto ahí.
extension View {
    @ViewBuilder
    func botonDeVidrio() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.plain)
        }
    }
}

/// Agrupa varios elementos de vidrio en una sola capa.
///
/// La guía oficial de Apple para adoptar Liquid Glass lo dice sin rodeos: si aplicas efectos de
/// vidrio a elementos propios, combínalos en un `GlassEffectContainer`, que optimiza el render y
/// hace que las formas se fundan entre sí al moverse. Tres botones sueltos abren tres capas.
///
/// En macOS 14 y 15 el contenedor no existe y esto es un `HStack` normal, que es lo correcto ahí.
struct ContenedorDeVidrio<Contenido: View>: View {
    @ViewBuilder let contenido: Contenido

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) { contenido }
            }
        } else {
            HStack(spacing: 6) { contenido }
        }
    }
}
