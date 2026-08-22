import Foundation

/// Inicio de sesión con el flujo de dispositivo de OAuth 2.0 (RFC 8628), que es lo que usa
/// `sentry-cli` y lo que Sentry documenta para clientes sin navegador propio.
///
/// Por qué este y no pedirle al usuario que pegue un token: un token pegado a mano suele venir
/// de reutilizar el que ya se tenía a mano, que es justamente el de CI y trae escritura. Acá la
/// aplicación DECLARA los permisos que necesita y el usuario aprueba exactamente esos.
///
/// Requiere Sentry 26.1.0 o superior. En instancias más viejas no existe el endpoint y hay que
/// caer al token pegado a mano, que es lo que hace `Ajustes`.
public struct FlujoDeDispositivo: Sendable {
    /// Identificador de cliente de la aplicación registrada en Sentry para Centinela.
    ///
    /// Va en el código a propósito. El RFC 8628 trata a estos clientes como **públicos**: no
    /// hay secreto que proteger, el identificador viaja en cada petición y su función es
    /// nombrar la aplicación en la pantalla donde la persona aprueba. `sentry-cli` hace lo
    /// mismo con el suyo. Quien prefiera registrar el propio lo pega en Ajustes y este queda
    /// sin usar.
    public static let clienteDeCentinela = "ba7385bf68de9e4f134f5c3da81d1080c822f04c5578556a0786c01a453219f2"

    /// Lo único que Centinela pide. No incluye ni `project:write` ni `event:write`, que sí pide
    /// `sentry-cli` porque sube sourcemaps.
    public static let permisos = ["org:read", "project:read", "event:read"]

    public struct Codigo: Sendable, Equatable {
        public let deviceCode: String
        public let userCode: String
        public let urlDeVerificacion: URL
        /// URL con el código ya incrustado. Cuando el servidor la manda, se abre esta y el
        /// usuario no tiene que teclear nada.
        public let urlCompleta: URL?
        public let expiraEn: TimeInterval
        /// Cada cuántos segundos se puede preguntar. El servidor puede subirlo con `slow_down`.
        public let intervalo: TimeInterval
    }

    public struct Concesion: Sendable, Equatable {
        public let tokenDeAcceso: String
        public let tokenDeRefresco: String?
        public let vence: Date
    }

    public enum Falla: LocalizedError, Sendable, Equatable {
        case clienteNoConfigurado
        case rechazadoPorLaPersona
        case codigoVencido
        case servidorNoSoportaElFlujo
        case respuesta(String)

        public var errorDescription: String? {
            switch self {
            case .clienteNoConfigurado:
                "Falta el identificador de cliente OAuth. Ver el README, sección «Iniciar sesión»."
            case .rechazadoPorLaPersona:
                "Se rechazó la autorización en el navegador."
            case .codigoVencido:
                "El código expiró antes de aprobarse. Vuelve a intentarlo."
            case .servidorNoSoportaElFlujo:
                "Este servidor de Sentry no soporta el flujo de dispositivo (requiere 26.1.0 o superior). Usa un token."
            case .respuesta(let detalle):
                "Sentry respondió: \(detalle)"
            }
        }
    }

    private let host: URL
    private let clientID: String
    private let sesion: URLSession

    public init(host: URL, clientID: String, sesion: URLSession = .shared) {
        self.host = host
        self.clientID = clientID
        self.sesion = sesion
    }

    // MARK: - Paso 1: pedir el código

    public func solicitarCodigo() async throws -> Codigo {
        guard !clientID.isEmpty else { throw Falla.clienteNoConfigurado }

        let cuerpo = try await postFormulario("oauth/device/code/", [
            "client_id": clientID,
            "scope": Self.permisos.joined(separator: " ")
        ])
        guard
            let deviceCode = cuerpo["device_code"] as? String,
            let userCode = cuerpo["user_code"] as? String,
            let uri = cuerpo["verification_uri"] as? String,
            let url = URL(string: uri)
        else { throw Falla.respuesta("respuesta de device/code incompleta") }

        return Codigo(
            deviceCode: deviceCode,
            userCode: userCode,
            urlDeVerificacion: url,
            urlCompleta: (cuerpo["verification_uri_complete"] as? String).flatMap(URL.init(string:)),
            // Los valores por omisión son los que manda el RFC 8628 cuando el servidor los omite.
            expiraEn: (cuerpo["expires_in"] as? NSNumber)?.doubleValue ?? 600,
            intervalo: (cuerpo["interval"] as? NSNumber)?.doubleValue ?? 5
        )
    }

    // MARK: - Paso 2: esperar a que la persona apruebe

    /// Pregunta cada `intervalo` segundos hasta que el usuario apruebe, rechace o el código
    /// venza. `dormir` se inyecta para que los tests no esperen de verdad.
    public func esperarAutorizacion(
        _ codigo: Codigo,
        dormir: @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
    ) async throws -> Concesion {
        var intervalo = codigo.intervalo
        let limite = Date().addingTimeInterval(codigo.expiraEn)

        while Date() < limite {
            try await dormir(intervalo)
            let cuerpo = try? await postFormulario("oauth/token/", [
                "client_id": clientID,
                "device_code": codigo.deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
            ])
            guard let cuerpo else { continue }

            if let token = cuerpo["access_token"] as? String {
                let vida = (cuerpo["expires_in"] as? NSNumber)?.doubleValue ?? 3600
                return Concesion(
                    tokenDeAcceso: token,
                    tokenDeRefresco: cuerpo["refresh_token"] as? String,
                    vence: Date().addingTimeInterval(vida)
                )
            }

            switch cuerpo["error"] as? String {
            case "authorization_pending", nil:
                continue
            case "slow_down":
                // El RFC manda subir el intervalo 5 segundos cada vez que llega este error.
                // Ignorarlo hace que el servidor siga respondiendo `slow_down` para siempre.
                intervalo += 5
            case "access_denied":
                throw Falla.rechazadoPorLaPersona
            case "expired_token":
                throw Falla.codigoVencido
            case .some(let otro):
                throw Falla.respuesta(otro)
            }
        }
        throw Falla.codigoVencido
    }

    // MARK: - Paso 3: renovar antes de que venza

    public func refrescar(_ tokenDeRefresco: String) async throws -> Concesion {
        let cuerpo = try await postFormulario("oauth/token/", [
            "client_id": clientID,
            "refresh_token": tokenDeRefresco,
            "grant_type": "refresh_token"
        ])
        guard let token = cuerpo["access_token"] as? String else {
            throw Falla.respuesta((cuerpo["error"] as? String) ?? "refresh sin access_token")
        }
        let vida = (cuerpo["expires_in"] as? NSNumber)?.doubleValue ?? 3600
        return Concesion(
            tokenDeAcceso: token,
            // Sentry rota el token de refresco: si viene uno nuevo hay que quedarse con ese, y
            // si no viene, el viejo sigue sirviendo. Guardar `nil` a ciegas cierra la sesión.
            tokenDeRefresco: (cuerpo["refresh_token"] as? String) ?? tokenDeRefresco,
            vence: Date().addingTimeInterval(vida)
        )
    }

    /// `sentry-cli` renueva cuando queda menos del 10 % de la vida del token. Se copia el
    /// criterio para no inventar uno propio.
    public static func convieneRefrescar(vence: Date, vida: TimeInterval, ahora: Date = .now) -> Bool {
        vence.timeIntervalSince(ahora) < vida * 0.1
    }

    // MARK: - Transporte

    private func postFormulario(_ ruta: String, _ campos: [String: String]) async throws -> [String: Any] {
        var componentes = URLComponents()
        componentes.queryItems = campos.map { URLQueryItem(name: $0.key, value: $0.value) }
        let cuerpo = componentes.percentEncodedQuery ?? ""

        var peticion = URLRequest(url: host.appendingPathComponent(ruta))
        peticion.httpMethod = "POST"
        peticion.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        peticion.httpBody = Data(cuerpo.utf8)

        let (datos, respuesta) = try await sesion.data(for: peticion)
        // 404 significa que la instancia es anterior a 26.1.0 y el endpoint no existe. Es
        // distinto de un error del flujo y merece un mensaje distinto.
        if let http = respuesta as? HTTPURLResponse, http.statusCode == 404 {
            throw Falla.servidorNoSoportaElFlujo
        }
        guard let json = try? JSONSerialization.jsonObject(with: datos) as? [String: Any] else {
            throw Falla.respuesta("cuerpo que no es JSON")
        }
        return json
    }
}
