import CentinelaCore
import SwiftUI

@main
struct CentinelaApp: App {
    @State private var estado = Estado()

    var body: some Scene {
        MenuBarExtra {
            PanelPrincipal(estado: estado)
        } label: {
            EtiquetaDeBarra(estado: estado)
                // El arranque cuelga de la etiqueta y no de `init()` porque la etiqueta existe
                // desde que la aplicación aparece en la barra, mientras que el panel no se
                // construye hasta el primer despliegue. Un `.task` en el panel dejaría el
                // número sin poblar hasta que alguien hiciera clic.
                .task {
                    estado.arrancar()
                    await estado.revisarPoderDelToken()
                }
        }
        // `.window` y no `.menu`: un `NSMenu` no puede dibujar la chispa ni una lista con dos
        // líneas por fila. El costo es que el panel es una ventana de verdad, que macOS crea
        // recién al primer despliegue.
        .menuBarExtraStyle(.window)

        Settings {
            Preferencias(estado: estado)
        }
    }
}
