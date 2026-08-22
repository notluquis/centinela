import CentinelaCore
import SwiftUI

struct Preferencias: View {
    let estado: Estado
    @State private var token: String = ""
    @State private var guardado = false
    @State private var arranque = ArranqueConLaSesion()

    private var ajustes: Ajustes { estado.ajustes }

    var body: some View {
        Form {
            Section {
                TextField("Organización", text: Binding(
                    get: { ajustes.organizacion },
                    set: { ajustes.organizacion = $0.trimmingCharacters(in: .whitespaces) }
                ))
                .help("El identificador que aparece en la URL: sentry.io/organizations/AQUÍ/")

                TextField("Servidor", text: Binding(
                    get: { ajustes.host },
                    set: { ajustes.host = $0.trimmingCharacters(in: .whitespaces) }
                ))
                .help("https://sentry.io, o la URL de tu instancia propia.")

                SecureField("Token", text: $token)
                HStack {
                    Button("Guardar token") {
                        ajustes.token = token.trimmingCharacters(in: .whitespaces)
                        token = ""
                        guardado = true
                        Task {
                            await estado.revisarPoderDelToken()
                            await estado.refrescarLoBarato()
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
                        ajustes.token = ""
                        token = ""
                        guardado = false
                    }
                }
                Text("El token se guarda en el llavero de macOS, nunca en un archivo. Dale sólo `org:read`, `project:read` y `event:read`: Centinela no escribe nada en Sentry.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Cuenta")
            }

            Section {
                Picker("Ventana", selection: Binding(
                    get: { ajustes.ventana },
                    set: { ajustes.ventana = $0 }
                )) {
                    ForEach(Ventana.allCases, id: \.self) { v in
                        Text(v.etiqueta).tag(v)
                    }
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

                Stepper("Mostrar \(ajustes.maximoIssues) incidencias", value: Binding(
                    get: { ajustes.maximoIssues },
                    set: { ajustes.maximoIssues = $0 }
                ), in: 5...50, step: 5)
                Toggle("Arrancar al iniciar sesión", isOn: Binding(
                    get: { arranque.activo },
                    set: { arranque.alternar($0) }
                ))
                if arranque.necesitaAprobacion {
                    HStack {
                        Text("Falta aprobarlo en Ajustes del Sistema. Una aplicación no puede aprobarse sola.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Abrir", action: arranque.abrirAjustesDelSistema)
                    }
                }
                if let error = arranque.ultimoError {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
            } header: {
                Text("Consulta")
            } footer: {
                Text("Cada ciclo pide dos rutas baratas (la serie de errores y el estado de uptime). La lista de incidencias, que es diez veces más pesada, se pide sólo al abrir el panel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .padding()
    }
}
