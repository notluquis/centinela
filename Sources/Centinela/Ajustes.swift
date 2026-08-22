import CentinelaCore
import Foundation
import Observation

/// Preferencias del usuario. El token NO está acá: vive en el llavero (ver `Llavero`).
/// `UserDefaults` se respalda y se sincroniza; un token de organización de Sentry no debería.
@MainActor
@Observable
final class Ajustes {
    static let cuentaDelToken = "token-de-organizacion"
    static let cuentaDelRefresco = "token-de-refresco"

    var organizacion: String {
        didSet { defaults.set(organizacion, forKey: "organizacion") }
    }

    var host: String {
        didSet { defaults.set(host, forKey: "host") }
    }

    var ventana: Ventana {
        didSet { defaults.set(ventana.rawValue, forKey: "ventana") }
    }

    /// Cinco minutos por defecto. Con el límite medido de la API (40 peticiones por ventana
    /// por ruta, 25 concurrentes) se podría pedir mucho más seguido; el techo no es Sentry
    /// sino la batería y el hecho de que un error que apareció hace tres minutos no se
    /// atiende distinto que uno de hace cinco.
    var intervaloSegundos: TimeInterval {
        didSet { defaults.set(intervaloSegundos, forKey: "intervaloSegundos") }
    }

    var maximoIssues: Int {
        didSet { defaults.set(maximoIssues, forKey: "maximoIssues") }
    }

    /// Identificador de cliente OAuth para el flujo de dispositivo. Vacío significa "sin
    /// inicio de sesión": la aplicación cae a pedir un token pegado a mano, que sigue siendo
    /// válido. No es un secreto (RFC 8628 lo trata como cliente público), así que va en
    /// `UserDefaults` y no en el llavero.
    var clientIDOAuth: String {
        didSet { defaults.set(clientIDOAuth, forKey: "clientIDOAuth") }
    }

    /// Cuándo vence el token de acceso. Sólo aplica a los tokens obtenidos por OAuth; un token
    /// pegado a mano no vence solo y acá queda en `nil`.
    var venceElToken: Date? {
        didSet { defaults.set(venceElToken?.timeIntervalSince1970 ?? 0, forKey: "venceElToken") }
    }

    /// Cuánto duraba el token cuando se emitió, para saber qué es "menos del 10 % de vida".
    var vidaDelToken: TimeInterval {
        didSet { defaults.set(vidaDelToken, forKey: "vidaDelToken") }
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
        clientIDOAuth = defaults.string(forKey: "clientIDOAuth") ?? ""
        let vence = defaults.double(forKey: "venceElToken")
        venceElToken = vence > 0 ? Date(timeIntervalSince1970: vence) : nil
        let vida = defaults.double(forKey: "vidaDelToken")
        vidaDelToken = vida > 0 ? vida : 3600
    }

    var tokenDeRefresco: String? {
        (try? Llavero.leer(cuenta: Self.cuentaDelRefresco)) ?? nil
    }

    /// Guarda lo que devolvió el flujo de dispositivo. Devuelve `false` si el llavero rechazó
    /// algo, igual que `guardarToken`: quien llama no debe asumir que salió bien.
    @discardableResult
    func guardarSesion(_ concesion: FlujoDeDispositivo.Concesion) -> Bool {
        guard guardarToken(concesion.tokenDeAcceso) else { return false }
        do {
            if let refresco = concesion.tokenDeRefresco {
                try Llavero.guardar(refresco, cuenta: Self.cuentaDelRefresco)
            }
            vidaDelToken = max(concesion.vence.timeIntervalSinceNow, 60)
            venceElToken = concesion.vence
            return true
        } catch {
            ultimoErrorDeLlavero = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func cerrarSesion() {
        guardarToken("")
        try? Llavero.borrar(cuenta: Self.cuentaDelRefresco)
        venceElToken = nil
    }

    /// `true` cuando hay sesión OAuth y al token le queda menos del 10 % de vida.
    var convieneRefrescar: Bool {
        guard let vence = venceElToken, tokenDeRefresco != nil else { return false }
        return FlujoDeDispositivo.convieneRefrescar(vence: vence, vida: vidaDelToken)
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

    /// Copia en memoria del token. El llavero es una llamada sincrónica al sistema y `token`
    /// lo consulta `configurado`, que SwiftUI reevalúa en CADA dibujo del panel: sin esta caché
    /// el panel toca el llavero decenas de veces por segundo mientras está abierto.
    @ObservationIgnored private var tokenEnMemoria: String?

    var token: String {
        if let tokenEnMemoria { return tokenEnMemoria }
        let valor = (try? Llavero.leer(cuenta: Self.cuentaDelToken)).flatMap { $0 } ?? ""
        tokenEnMemoria = valor
        return valor
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
            tokenEnMemoria = nuevo
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
