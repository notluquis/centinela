import AppKit
import CentinelaCore
import SwiftUI

/// Pestaña "Acerca de", con el mismo contenido que Stats y TheBoringNotch ponen en la suya:
/// qué versión corre, dónde vive el código, y si hay algo más nuevo.
struct AcercaDe: View {
    private static let licencia = URL(
        string: "https://github.com/\(Estado.repositorio)/blob/main/LICENSE"
    )!

    let estado: Estado
    @State private var buscando = false

    var body: some View {
        VStack(spacing: 14) {
            if let icono = NSApplication.shared.applicationIconImage {
                Image(nsImage: icono)
                    .resizable()
                    .frame(width: 96, height: 96)
            }
            Text("Centinela").font(.title2.weight(.semibold))
            Text("Versión \(estado.versionInstalada)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if let novedad = estado.novedad {
                Link("Hay una versión \(novedad.version.description)", destination: novedad.pagina)
                    .font(.callout)
            } else {
                HStack(spacing: 6) {
                    if buscando { ProgressView().controlSize(.small) }
                    Button("Buscar actualizaciones") {
                        buscando = true
                        Task {
                            await estado.buscarActualizacion(forzar: true)
                            buscando = false
                        }
                    }
                    .disabled(buscando)
                }
            }

            // Sparkle NO: su documentación de caja de arena dice que una firma ad-hoc no sirve
            // para distribuir, y pide incrustar Installer.xpc más dos excepciones de mach-lookup.
            // Esto avisa y abre la página; bajar y reemplazar es cosa de la persona.
            Text("Centinela avisa de versiones nuevas, no se actualiza sola: la firma es ad-hoc"
                + " y un instalador automático chocaría con Gatekeeper igual.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 16) {
                Link("Código", destination: URL(string: "https://github.com/\(Estado.repositorio)")!)
                Link("Licencia MIT", destination: Self.licencia)
                Link("Reportar algo", destination: URL(string: "https://github.com/\(Estado.repositorio)/issues")!)
            }
            .font(.callout)

            Text("Sin relación con Sentry (Functional Software, Inc.). Usa su API pública de lectura.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
