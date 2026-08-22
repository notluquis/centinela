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

    var token: String {
        get { (try? Llavero.leer(cuenta: Self.cuentaDelToken)) .flatMap { $0 } ?? "" }
        set {
            if newValue.isEmpty {
                try? Llavero.borrar(cuenta: Self.cuentaDelToken)
            } else {
                try? Llavero.guardar(newValue, cuenta: Self.cuentaDelToken)
            }
        }
    }

    var configurado: Bool { !organizacion.isEmpty && !token.isEmpty }

    func credenciales() -> Credenciales? {
        let t = token
        guard !t.isEmpty, !organizacion.isEmpty, let url = URL(string: host) else { return nil }
        return Credenciales(token: t, organizacion: organizacion, host: url)
    }
}
