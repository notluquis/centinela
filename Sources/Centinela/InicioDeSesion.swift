import AppKit
import CentinelaCore
import Observation

/// Conduce el flujo de dispositivo desde la interfaz y guarda el resultado.
@MainActor
@Observable
final class InicioDeSesion {
    enum Etapa: Equatable {
        case inactivo
        case pidiendoCodigo
        case esperandoAprobacion(codigo: String, url: URL)
        case listo
        case falló(String)
    }

    private(set) var etapa: Etapa = .inactivo

    /// Se llena cuando el token llega a más de una organización y hay que elegir.
    private(set) var organizacionesParaElegir: [Organizacion] = []

    private let ajustes: Ajustes
    @ObservationIgnored private var tarea: Task<Void, Never>?

    init(ajustes: Ajustes) { self.ajustes = ajustes }

    var enCurso: Bool {
        switch etapa {
        case .pidiendoCodigo, .esperandoAprobacion: true
        default: false
        }
    }

    func entrar() {
        cancelar()
        etapa = .pidiendoCodigo
        let flujo = FlujoDeDispositivo(
            host: URL(string: ajustes.host) ?? URL(string: "https://sentry.io")!,
            clientID: ajustes.clientIDOAuth
        )
        tarea = Task { [weak self] in
            guard let self else { return }
            do {
                let codigo = try await flujo.solicitarCodigo()
                etapa = .esperandoAprobacion(codigo: codigo.userCode, url: codigo.urlDeVerificacion)
                // Se abre la URL con el código ya incrustado cuando el servidor la manda: así
                // la persona aprueba con un clic en vez de teclear ocho caracteres. El código
                // se muestra igual, porque el navegador puede abrirse en otro perfil sin sesión.
                NSWorkspace.shared.open(codigo.urlCompleta ?? codigo.urlDeVerificacion)

                let concesion = try await flujo.esperarAutorizacion(codigo)
                guard ajustes.guardarSesion(concesion) else {
                    etapa = .falló(ajustes.ultimoErrorDeLlavero ?? "no se pudo guardar en el llavero")
                    return
                }
                await resolverOrganizacion()
                etapa = .listo
            } catch is CancellationError {
                etapa = .inactivo
            } catch {
                etapa = .falló((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    /// El flujo de dispositivo entrega un token y NADA MÁS: ni la organización ni el proyecto.
    ///
    /// Sin este paso, alguien iniciaba sesión con éxito y la aplicación seguía mostrando "Falta
    /// configurar" para siempre, porque `Ajustes.configurado` exige una organización y ninguna
    /// capa reportaba error: el token estaba guardado, la etapa decía `.listo`, y el ciclo se
    /// devolvía en el `guard let cliente`. Un fallo en silencio con todo verde.
    private func resolverOrganizacion() async {
        guard ajustes.organizacion.isEmpty else { return }
        // La organización va vacía a propósito: esta llamada NO cuelga de una, y es
        // precisamente la que se hace para averiguar cuál es.
        let credenciales = Credenciales(
            token: ajustes.token,
            organizacion: "",
            host: URL(string: ajustes.host) ?? URL(string: "https://sentry.io")!
        )

        do {
            let organizaciones = try await ClienteDeSentry(credenciales: credenciales).organizaciones()
            switch organizaciones.count {
            case 0:
                etapa = .falló("El token no llega a ninguna organización.")
            case 1:
                ajustes.organizacion = organizaciones[0].slug
            default:
                // Con varias no se adivina: se muestran y la persona elige.
                organizacionesParaElegir = organizaciones
            }
        } catch {
            etapa = .falló((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func elegir(_ organizacion: Organizacion) {
        ajustes.organizacion = organizacion.slug
        organizacionesParaElegir = []
    }

    func cancelar() {
        tarea?.cancel()
        tarea = nil
        etapa = .inactivo
    }

    /// Renueva el token si le queda poca vida. Se llama antes de cada ciclo, no en un
    /// temporizador propio: si la aplicación estuvo dormida tres días, lo que importa es
    /// renovar cuando vuelve, no haber intentado mientras no había red.
    /// Devuelve el error si lo hubo, para que quien llama decida dónde mostrarlo.
    @discardableResult
    func refrescarSiHaceFalta() async -> String? {
        guard ajustes.convieneRefrescar, let refresco = ajustes.tokenDeRefresco else { return nil }
        let flujo = FlujoDeDispositivo(
            host: URL(string: ajustes.host) ?? URL(string: "https://sentry.io")!,
            clientID: ajustes.clientIDOAuth
        )
        do {
            ajustes.guardarSesion(try await flujo.refrescar(refresco))
            return nil
        } catch {
            // Un fallo de renovación NO cierra la sesión: puede ser que no haya red. El token
            // viejo sigue guardado y el ciclo siguiente vuelve a intentar. Si de verdad está
            // revocado, la API responde 401 y eso sí se le muestra al usuario.
            //
            // Y NO se toca `etapa`: eso es lo que mira la ventana de Ajustes, así que un corte
            // de red de dos segundos durante un ciclo de fondo cambiaría "Sesión iniciada" por
            // un error con botón de reintentar, que es mentira. El aviso va al panel, junto al
            // resto de los errores de red.
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
