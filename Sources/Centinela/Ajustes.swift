import CentinelaCore
import Foundation
import Observation

/// Preferencias del usuario. El token NO está acá: vive en el llavero (ver `Llavero`).
/// `UserDefaults` se respalda y se sincroniza; un token de organización de Sentry no debería.
@MainActor
@Observable
final class Ajustes {
    static let cuentaDelToken = "token-de-organizacion"

    var organizacion: String {
        didSet { defaults.set(organizacion, forKey: "organizacion") }
    }

    var host: String {
        didSet { defaults.set(host, forKey: "host") }
    }

    var ventana: Ventana {
        didSet { defaults.set(ventana.rawValue, forKey: "ventana") }
    }

    /// Cinco minutos por defecto. Con el límite medido de la API —40 peticiones por ventana
    /// por ruta, 25 concurrentes— se podría pedir mucho más seguido; el techo no es Sentry
    /// sino la batería y el hecho de que un error que apareció hace tres minutos no se
    /// atiende distinto que uno de hace cinco.
    var intervaloSegundos: TimeInterval {
        didSet { defaults.set(intervaloSegundos, forKey: "intervaloSegundos") }
    }

    var maximoIssues: Int {
        didSet { defaults.set(maximoIssues, forKey: "maximoIssues") }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        organizacion = defaults.string(forKey: "organizacion") ?? ""
        host = defaults.string(forKey: "host") ?? "https://sentry.io"
        ventana = Ventana(rawValue: defaults.string(forKey: "ventana") ?? "") ?? .veinticuatroHoras
        let guardado = defaults.double(forKey: "intervaloSegundos")
        intervaloSegundos = guardado > 0 ? guardado : 300
        let tope = defaults.integer(forKey: "maximoIssues")
        maximoIssues = tope > 0 ? tope : 15
    }

    /// Lo último que dijo el llavero cuando falló. `nil` si la última operación salió bien.
    ///
    /// Existe porque la versión anterior de esto usaba `try?` en las dos direcciones: una
    /// escritura fallida dejaba la interfaz mostrando "Guardado en el llavero" con su visto
    /// bueno, sin guardar nada, y la aplicación se quedaba en "Falta configurar" para siempre
    /// sin un error en ninguna parte. El modo de falla no es teórico: una firma ad-hoc no
    /// carga `application-identifier`, y sin él el grupo de acceso al llavero puede no existir
    /// (`errSecMissingEntitlement`, -34018).
    var ultimoErrorDeLlavero: String?

    var token: String {
        do {
            let valor = try Llavero.leer(cuenta: Self.cuentaDelToken) ?? ""
            return valor
        } catch {
            // El getter no puede reportar sin volverse mutante; el error se recoge al escribir,
            // que es cuando el usuario está mirando.
            return ""
        }
    }

    /// Devuelve `true` si el llavero aceptó la operación. Quien llama NO debe asumir que sí.
    @discardableResult
    func guardarToken(_ nuevo: String) -> Bool {
        do {
            if nuevo.isEmpty {
                try Llavero.borrar(cuenta: Self.cuentaDelToken)
            } else {
                try Llavero.guardar(nuevo, cuenta: Self.cuentaDelToken)
            }
            ultimoErrorDeLlavero = nil
            return true
        } catch {
            ultimoErrorDeLlavero = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    var configurado: Bool { !organizacion.isEmpty && !token.isEmpty }

    func credenciales() -> Credenciales? {
        let t = token
        guard !t.isEmpty, !organizacion.isEmpty, let url = URL(string: host) else { return nil }
        return Credenciales(token: t, organizacion: organizacion, host: url)
    }
}
