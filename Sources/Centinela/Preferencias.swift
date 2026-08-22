import CentinelaCore
import SwiftUI

/// Ventana de preferencias con pestañas, que es la convención de macOS para ajustes de una
/// aplicación de barra de menús (Stats y TheBoringNotch hacen lo mismo con una barra lateral,
/// que es la variante para muchas más secciones que estas dos).
struct Preferencias: View {
    let estado: Estado

    var body: some View {
        // `.tabItem` y no el tipo `Tab`: ese llegó en macOS 15 y el objetivo de despliegue es
        // 14. La apariencia es la misma en ambas.
        TabView {
            PestanaDeCuenta(estado: estado)
                .tabItem { Label("Cuenta", systemImage: "person.badge.key") }
            PestanaDeConsulta(estado: estado)
                .tabItem { Label("Consulta", systemImage: "slider.horizontal.3") }
            AcercaDe(estado: estado)
                .tabItem { Label("Acerca de", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 430)
    }
}

// MARK: - Cuenta

private struct PestanaDeCuenta: View {
    let estado: Estado
    @State private var token = ""
    @State private var guardado = false

    private var ajustes: Ajustes { estado.ajustes }
    private var sesion: InicioDeSesion { estado.sesion }

    var body: some View {
        Form {
            Section("Organización") {
                TextField("Identificador", text: Binding(
                    get: { ajustes.organizacion },
                    set: { ajustes.organizacion = $0.trimmingCharacters(in: .whitespaces) }
                ))
                .help("El identificador que aparece en la URL: sentry.io/organizations/AQUÍ/")

                TextField("Servidor", text: Binding(
                    get: { ajustes.host },
                    set: { ajustes.host = $0.trimmingCharacters(in: .whitespaces) }
                ))
            }

            Section("Iniciar sesión") {
                switch sesion.etapa {
                case .esperandoAprobacion(let codigo, let url):
                    LabeledContent("Código") {
                        Text(codigo)
                            .font(.system(.title3, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    Text("Apruébalo en el navegador. Si no se abrió solo, entra a \(url.absoluteString) y escribe el código.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Cancelar", role: .cancel, action: sesion.cancelar)

                case .pidiendoCodigo:
                    HStack { ProgressView().controlSize(.small); Text("Pidiendo el código…") }

                case .listo:
                    Label("Sesión iniciada. Sentry entregó sólo los permisos de lectura que se le pidieron.",
                          systemImage: "checkmark.seal")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Cerrar sesión", role: .destructive) { ajustes.cerrarSesion() }

                case .falló(let error):
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Reintentar", action: sesion.entrar)

                case .inactivo:
                    Button("Iniciar sesión con Sentry", action: sesion.entrar)
                        .disabled(ajustes.clientIDOAuth.isEmpty)
                    if ajustes.clientIDOAuth.isEmpty {
                        Text("Falta el identificador de cliente OAuth. Ver el README, sección «Iniciar sesión». Mientras tanto puedes pegar un token abajo.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                TextField("Identificador de cliente OAuth", text: Binding(
                    get: { ajustes.clientIDOAuth },
                    set: { ajustes.clientIDOAuth = $0.trimmingCharacters(in: .whitespaces) }
                ))
                .help("Se obtiene creando una integración en Sentry: Settings, Developer Settings.")
            }

            Section("O pega un token") {
                SecureField("Token", text: $token)
                HStack {
                    Button("Guardar token") {
                        // El visto bueno se pinta SÓLO si el llavero aceptó.
                        guardado = ajustes.guardarToken(token.trimmingCharacters(in: .whitespaces))
                        if guardado {
                            token = ""
                            Task {
                                await estado.revisarPoderDelToken()
                                await estado.refrescarLoBarato()
                            }
                        }
                    }
                    .disabled(token.isEmpty)

                    if guardado {
                        Label("Guardado en el llavero", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Borrar", role: .destructive) {
                        ajustes.cerrarSesion()
                        token = ""
                        guardado = false
                    }
                }
                if let error = ajustes.ultimoErrorDeLlavero {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Dale sólo `org:read`, `project:read` y `event:read`: Centinela no escribe nada en Sentry. El token se guarda en el llavero, nunca en un archivo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Consulta

private struct PestanaDeConsulta: View {
    let estado: Estado
    @State private var arranque = ArranqueConLaSesion()

    private var ajustes: Ajustes { estado.ajustes }

    var body: some View {
        Form {
            Section {
                Picker("Ventana", selection: Binding(
                    get: { ajustes.ventana },
                    set: { ajustes.ventana = $0 }
                )) {
                    ForEach(Ventana.allCases, id: \.self) { Text($0.etiqueta).tag($0) }
                }

                Picker("Refrescar cada", selection: Binding(
                    get: { ajustes.intervaloSegundos },
                    set: { ajustes.intervaloSegundos = $0; estado.reprogramar() }
                )) {
                    Text("1 minuto").tag(TimeInterval(60))
                    Text("5 minutos").tag(TimeInterval(300))
                    Text("15 minutos").tag(TimeInterval(900))
                    Text("1 hora").tag(TimeInterval(3600))
                }

                Stepper("Mostrar \(ajustes.maximoIssues) issues", value: Binding(
                    get: { ajustes.maximoIssues },
                    set: { ajustes.maximoIssues = $0 }
                ), in: 5...50, step: 5)
            } footer: {
                Text("Cada ciclo pide dos rutas baratas (la serie de errores y el estado de uptime). La lista de issues, que es diez veces más pesada, se pide sólo al abrir el panel. Sentry no ofrece webhooks a una aplicación de escritorio: sus notificaciones necesitan una URL pública.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Sistema") {
                Toggle("Arrancar al iniciar sesión", isOn: Binding(
                    get: { arranque.activo },
                    set: { arranque.alternar($0) }
                ))
                if arranque.necesitaAprobacion {
                    HStack {
                        Text("Falta aprobarlo en Ajustes del Sistema. Una aplicación no puede aprobarse sola.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Abrir", action: arranque.abrirAjustesDelSistema)
                    }
                }
                if let error = arranque.ultimoError {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
    }
}
