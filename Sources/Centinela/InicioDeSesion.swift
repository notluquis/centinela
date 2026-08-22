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
                etapa = ajustes.guardarSesion(concesion)
                    ? .listo
                    : .falló(ajustes.ultimoErrorDeLlavero ?? "no se pudo guardar en el llavero")
            } catch is CancellationError {
                etapa = .inactivo
            } catch {
                etapa = .falló((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    func cancelar() {
        tarea?.cancel()
        tarea = nil
        etapa = .inactivo
    }

    /// Renueva el token si le queda poca vida. Se llama antes de cada ciclo, no en un
    /// temporizador propio: si la aplicación estuvo dormida tres días, lo que importa es
    /// renovar cuando vuelve, no haber intentado mientras no había red.
    func refrescarSiHaceFalta() async {
        guard ajustes.convieneRefrescar, let refresco = ajustes.tokenDeRefresco else { return }
        let flujo = FlujoDeDispositivo(
            host: URL(string: ajustes.host) ?? URL(string: "https://sentry.io")!,
            clientID: ajustes.clientIDOAuth
        )
        do {
            ajustes.guardarSesion(try await flujo.refrescar(refresco))
        } catch {
            // Un fallo de renovación NO cierra la sesión: puede ser que no haya red. El token
            // viejo sigue guardado y el ciclo siguiente vuelve a intentar. Si de verdad está
            // revocado, la API responde 401 y eso sí se le muestra al usuario.
            etapa = .falló((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
