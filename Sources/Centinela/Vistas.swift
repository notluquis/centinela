import CentinelaCore
import SwiftUI

// MARK: - Lo que se ve arriba, en la barra

struct EtiquetaDeBarra: View {
    let estado: Estado

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: simbolo)
            if estado.totalDeErrores > 0 {
                Text(estado.totalDeErrores, format: .number)
            }
            // Como imagen y no como `Path` en vivo: la etiqueta de un `MenuBarExtra` la
            // dibuja el sistema en la barra, y ahí `Text` e `Image` son lo único que se
            // renderiza de forma confiable. Una forma vectorial se veía en el panel y NO en la
            // barra, que es justo donde se quería.
            if let chispa = Chispa.imagen(estado.serie.puntos.map(\.cantidad)) {
                Image(nsImage: chispa)
            }
        }
        .accessibilityLabel(descripcionAccesible)
        // Sin color fijo: en la barra de macOS 26 y 27 el fondo es transparente y encima va el
        // fondo de escritorio, así que un color propio deja de contrastar según el papel tapiz.
        // El símbolo de plantilla lo resuelve el sistema, que es quien sabe si está en claro o
        // en oscuro. Se pinta de rojo sólo la caída, que es el único estado que justifica
        // romper esa regla.
        .foregroundStyle(estado.hayCaida ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
    }

    private var simbolo: String {
        if estado.hayCaida { return "bolt.horizontal.circle.fill" }
        return estado.totalDeErrores > 0 ? "exclamationmark.triangle.fill" : "checkmark.seal"
    }

    private var descripcionAccesible: String {
        var partes = [Chispa.resumen(estado.serie.puntos.map(\.cantidad), ventana: estado.ajustes.ventana)]
        if estado.hayCaida { partes.insert("Hay un servicio caído.", at: 0) }
        return partes.joined(separator: " ")
    }
}

/// Dibuja la chispa. La aritmética vive en `Chispa.normalizar`, que sí tiene tests.
struct TrazoDeChispa: View {
    let valores: [Int]

    var body: some View {
        GeometryReader { geo in
            Path { trazo in
                let puntos = Chispa.normalizar(valores)
                guard puntos.count > 1 else { return }
                for (indice, punto) in puntos.enumerated() {
                    // `y` viene con 0 abajo; en Core Graphics 0 es arriba.
                    let sitio = CGPoint(x: punto.x * geo.size.width, y: (1 - punto.y) * geo.size.height)
                    if indice == 0 { trazo.move(to: sitio) } else { trazo.addLine(to: sitio) }
                }
            }
            .stroke(style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

// MARK: - El panel

struct PanelPrincipal: View {
    let estado: Estado
    @Environment(\.openSettings) private var abrirAjustes

    /// Una aplicación `LSUIElement` no es la aplicación activa, así que la ventana de Ajustes
    /// se abre DETRÁS de todo lo demás: el usuario hace clic, no pasa nada visible, y concluye
    /// que el botón está roto. Hay que activarse antes de pedirla.
    private func abrirAjustesAlFrente() {
        NSApplication.shared.activate()
        abrirAjustes()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !estado.ajustes.configurado {
                SinConfigurar(abrir: abrirAjustesAlFrente)
            } else {
                Encabezado(estado: estado)
                Divider()
                Contenido(estado: estado)
            }
            Divider()
            PieDePanel(estado: estado, abrirAjustes: abrirAjustesAlFrente)
        }
        .frame(width: 380)
        // El panel es lo único que pide la ruta cara: 1047 ms y 10,6 KB por apertura.
        .task { await estado.refrescarLoCaro() }
    }
}

private struct Encabezado: View {
    let estado: Estado

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(estado.totalDeErrores) errores")
                    .font(.title2.weight(.semibold))
                Text("en \(estado.ajustes.ventana.etiqueta)")
                    .foregroundStyle(.secondary)
                Spacer()
                if estado.cargando { ProgressView().controlSize(.small) }
            }
            TrazoDeChispa(valores: estado.serie.puntos.map(\.cantidad))
                .frame(height: 34)
                .foregroundStyle(.tint)
            ForEach(estado.monitores.filter(\.activo)) { monitor in
                HStack(spacing: 6) {
                    Circle()
                        .fill(monitor.sano ? .green : .red)
                        .frame(width: 7, height: 7)
                    Text(monitor.url.host() ?? monitor.name)
                        .font(.callout)
                    Spacer()
                    Text(monitor.sano ? "arriba" : "caído")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
    }
}

/// Mide el alto natural del contenido para que el `ScrollView` no colapse.
private struct AlturaDelContenido: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct Contenido: View {
    let estado: Estado
    @State private var alto: CGFloat = 0

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let error = estado.ultimoError {
                    Aviso(texto: error, simbolo: "exclamationmark.triangle", color: .orange)
                }
                if let novedad = estado.novedad {
                    Link(destination: novedad.pagina) {
                        Aviso(
                            texto: "Hay una versión \(novedad.version.description)."
                                + " Corres la \(estado.versionInstalada).",
                            simbolo: "arrow.down.circle",
                            color: .accentColor
                        )
                    }
                    .buttonStyle(.plain)
                }
                if let aviso = estado.deprecacion {
                    // Ver `AvisoDeDeprecacion`: Sentry avisa por encabezado antes de apagar
                    // una ruta. Sin esto, la aplicación se enteraría el día que se rompe.
                    Aviso(
                        texto: "Sentry va a retirar `\(aviso.ruta)` el \(aviso.fecha)."
                            + (aviso.reemplazo.map { " Reemplazo: \($0)." } ?? ""),
                        simbolo: "clock.badge.exclamationmark",
                        color: .orange
                    )
                }
                if estado.tokenConDemasiadoPoder {
                    // Ver `ClienteDeSentry.tokenPareceDeSoloLectura()`.
                    Aviso(
                        texto: "Este token puede leer la bitácora de auditoría, o sea trae permisos"
                            + " de escritura. Un widget no los necesita.",
                        simbolo: "key.slash",
                        color: .orange
                    )
                }
                Seccion(titulo: "Sin resolver", incidencias: estado.incidencias)
                if !estado.porRevisar.isEmpty {
                    Seccion(titulo: "Por revisar", incidencias: estado.porRevisar)
                }
                if !estado.releases.isEmpty {
                    Text("Últimos releases")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                    ForEach(estado.releases) { release in
                        HStack {
                            Text(release.etiqueta).font(.system(.callout, design: .monospaced))
                            Spacer()
                            Text("\(release.newGroups) nuevos")
                                .font(.caption)
                                .foregroundStyle(release.newGroups > 0 ? .orange : .secondary)
                            Text(release.dateCreated, format: .relative(presentation: .numeric))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 3)
                    }
                }
            }
            .padding(.bottom, 8)
            // Un `ScrollView` no tiene alto propio: dentro de un `VStack` sin alto definido
            // colapsa a CERO y su contenido desaparece sin dejar rastro, ni un hueco. Así se
            // veía el panel sin la lista de issues, con el pie pegado al encabezado. Se mide
            // el alto natural del contenido y se le da ese, con tope.
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: AlturaDelContenido.self, value: geo.size.height)
                }
            )
        }
        .onPreferenceChange(AlturaDelContenido.self) { alto = $0 }
        .frame(height: min(max(alto, 1), 420))
    }
}

private struct Seccion: View {
    let titulo: String
    let incidencias: [Incidencia]

    var body: some View {
        Text(titulo)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 10)
        if incidencias.isEmpty {
            Text("Nada acá.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
        }
        ForEach(incidencias) { incidencia in
            Link(destination: incidencia.permalink) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: incidencia.severidad.simbolo)
                        .foregroundStyle(incidencia.severidad == .warning ? .orange : .red)
                        .font(.caption)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(incidencia.title)
                            .lineLimit(2)
                            .font(.callout)
                        HStack(spacing: 6) {
                            Text(incidencia.project.slug)
                            Text("·")
                            Text("\(incidencia.count) eventos")
                            if incidencia.userCount > 0 {
                                Text("·")
                                Text("\(incidencia.userCount) personas")
                            }
                            Text("·")
                            Text(incidencia.lastSeen, format: .relative(presentation: .numeric))
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct Aviso: View {
    let texto: String
    let simbolo: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: simbolo).foregroundStyle(color)
            Text(texto).font(.caption)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}

private struct SinConfigurar: View {
    let abrir: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Falta configurar").font(.headline)
            Text("Centinela necesita el identificador de tu organización en Sentry y un token de sólo lectura.")
                .font(.callout)
                .foregroundStyle(.secondary)
                // Sin esto el texto se corta con puntos suspensivos en vez de envolver: dentro
                // de un contenedor de ancho fijo, un `Text` prefiere una sola línea salvo que
                // se le diga que puede crecer hacia abajo.
                .fixedSize(horizontal: false, vertical: true)
            Button("Abrir ajustes", action: abrir)
        }
        .padding(12)
    }
}

private struct PieDePanel: View {
    let estado: Estado
    let abrirAjustes: () -> Void

    var body: some View {
        HStack {
            if let cuando = estado.ultimaActualizacion {
                Text("Actualizado \(cuando, format: .relative(presentation: .numeric))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // Los tres botones van en un solo contenedor de vidrio. Es lo que pide la guía de
            // Apple: "combine custom Liquid Glass effects […] using a GlassEffectContainer,
            // which helps optimize performance while fluidly morphing Liquid Glass shapes into
            // each other". Sueltos, cada uno abre su propia capa.
            ContenedorDeVidrio {
                Button {
                    Task {
                        await estado.refrescarLoBarato()
                        await estado.refrescarLoCaro()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .botonDeVidrio()
                .help("Refrescar")

                Button(action: abrirAjustes) { Image(systemName: "gearshape") }
                    .botonDeVidrio()
                    .help("Ajustes")

                Button { NSApplication.shared.terminate(nil) } label: {
                    Image(systemName: "power")
                }
                .botonDeVidrio()
                .help("Salir")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
