import Foundation
import Testing

@testable import CentinelaCore

@Suite("Flujo de dispositivo (OAuth 2.0, RFC 8628)")
struct FlujoDeDispositivoTests {
        /// Cada test estrena sesión, y con ella su propia cola de respuestas. Por eso ya no hace
    /// falta ni `.serialized` ni limpiar entre tests.
    private func flujo(_ sesion: URLSession) -> FlujoDeDispositivo {
        FlujoDeDispositivo(
            host: URL(string: "https://sentry.example")!,
            clientID: "cliente-de-prueba",
            sesion: sesion
        )
    }

    private let codigoOK = """
    {"device_code":"DEV-1","user_code":"ABCD-EFGH",
     "verification_uri":"https://sentry.example/oauth/device/",
     "verification_uri_complete":"https://sentry.example/oauth/device/?user_code=ABCD-EFGH",
     "expires_in":600,"interval":5}
    """

    // MARK: - Los pasos

    @Test("Pedir el código devuelve lo que hay que mostrarle a la persona")
    func pedirCodigo() async throws {
        let sesion = Servidor.sesion()
        Servidor.encolar(sesion, "/oauth/device/code/", codigoOK)

        let codigo = try await flujo(sesion).solicitarCodigo()
        #expect(codigo.userCode == "ABCD-EFGH")
        #expect(codigo.deviceCode == "DEV-1")
        #expect(codigo.urlCompleta?.absoluteString.contains("ABCD-EFGH") == true)
        #expect(codigo.intervalo == 5)

        // Los permisos que se piden son parte del contrato con el usuario: si alguien agrega
        // `project:write` acá, el diálogo de Sentry se lo pide y este test se pone rojo.
        let enviado = try #require(Servidor.peticiones(sesion).first?.cuerpo)
        // Los dos puntos no se codifican (son válidos en una consulta) y el espacio va como
        // `%20`, que Django acepta igual que `+`.
        #expect(enviado.contains("scope=org:read%20project:read%20event:read"))
        #expect(!enviado.contains("write"))
    }

    @Test("Se espera mientras la persona no aprueba, y al aprobar devuelve el token")
    func esperaYAprobacion() async throws {
        let sesion = Servidor.sesion()
        Servidor.encolar(sesion, "/oauth/token/", #"{"error":"authorization_pending"}"#, estado: 400)
        Servidor.encolar(sesion, "/oauth/token/", #"{"error":"authorization_pending"}"#, estado: 400)
        Servidor.encolar(sesion, "/oauth/token/", #"{"access_token":"AT-1","refresh_token":"RT-1","expires_in":3600}"#)

        let codigo = FlujoDeDispositivo.Codigo(
            deviceCode: "DEV-1", userCode: "X", urlDeVerificacion: URL(string: "https://x")!,
            urlCompleta: nil, expiraEn: 600, intervalo: 5
        )
        let cronometro = Cronometro()
        let concesion = try await flujo(sesion).esperarAutorizacion(codigo) { cronometro.anotar($0) }

        #expect(concesion.tokenDeAcceso == "AT-1")
        #expect(concesion.tokenDeRefresco == "RT-1")
        #expect(cronometro.anotados == [5, 5, 5])
    }

    /// El RFC 8628 obliga a subir el intervalo 5 segundos cada vez que llega `slow_down`.
    /// Ignorarlo deja al cliente preguntando al mismo ritmo y el servidor sigue rechazando.
    @Test("`slow_down` sube el intervalo y no se queda pegado")
    func slowDown() async throws {
        let sesion = Servidor.sesion()
        Servidor.encolar(sesion, "/oauth/token/", #"{"error":"slow_down"}"#, estado: 400)
        Servidor.encolar(sesion, "/oauth/token/", #"{"error":"slow_down"}"#, estado: 400)
        Servidor.encolar(sesion, "/oauth/token/", #"{"access_token":"AT","expires_in":60}"#)

        let codigo = FlujoDeDispositivo.Codigo(
            deviceCode: "D", userCode: "X", urlDeVerificacion: URL(string: "https://x")!,
            urlCompleta: nil, expiraEn: 600, intervalo: 5
        )
        let cronometro = Cronometro()
        _ = try await flujo(sesion).esperarAutorizacion(codigo) { cronometro.anotar($0) }
        #expect(cronometro.anotados == [5, 10, 15])
    }

    @Test("Los dos finales malos del RFC llegan como errores distintos", arguments: [
        (#"{"error":"access_denied"}"#, FlujoDeDispositivo.Falla.rechazadoPorLaPersona),
        (#"{"error":"expired_token"}"#, FlujoDeDispositivo.Falla.codigoVencido)
    ])
    func finalesMalos(cuerpo: String, esperado: FlujoDeDispositivo.Falla) async {
        let sesion = Servidor.sesion()
        // 400, que es lo que devuelve sentry.io de verdad para los errores del RFC. Con 200
        // el test pasaría aunque el cliente lanzara ante cualquier no-2xx, que es un refactor
        // razonable y rompería el flujo entero.
        Servidor.encolar(sesion, "/oauth/token/", cuerpo, estado: 400)

        let codigo = FlujoDeDispositivo.Codigo(
            deviceCode: "D", userCode: "X", urlDeVerificacion: URL(string: "https://x")!,
            urlCompleta: nil, expiraEn: 600, intervalo: 1
        )
        await #expect(throws: esperado) {
            _ = try await flujo(sesion).esperarAutorizacion(codigo) { _ in }
        }
    }

    /// Sentry rota el token de refresco, pero no siempre manda uno nuevo. Guardar `nil` a ciegas
    /// cierra la sesión en la renovación siguiente, y el usuario tiene que volver a entrar sin
    /// entender por qué.
    @Test("Refrescar sin token nuevo conserva el viejo")
    func refrescoConservaElToken() async throws {
        let sesion = Servidor.sesion()
        Servidor.encolar(sesion, "/oauth/token/", #"{"access_token":"AT-2","expires_in":3600}"#)

        let concesion = try await flujo(sesion).refrescar("RT-VIEJO")
        #expect(concesion.tokenDeAcceso == "AT-2")
        #expect(concesion.tokenDeRefresco == "RT-VIEJO")
    }

    @Test("Refrescar con token nuevo se queda con el nuevo")
    func refrescoRota() async throws {
        let sesion = Servidor.sesion()
        let cuerpo = #"{"access_token":"AT-2","refresh_token":"RT-NUEVO","expires_in":3600}"#
        Servidor.encolar(sesion, "/oauth/token/", cuerpo)

        let concesion = try await flujo(sesion).refrescar("RT-VIEJO")
        #expect(concesion.tokenDeRefresco == "RT-NUEVO")
    }

    /// Una instancia anterior a Sentry 26.1.0 no tiene el endpoint. Un 404 tiene que leerse como
    /// "este servidor no soporta el flujo", no como un error genérico: la salida del usuario es
    /// distinta (pegar un token a mano).
    @Test("Un 404 se traduce a «este servidor no soporta el flujo»")
    func servidorViejo() async {
        let sesion = Servidor.sesion()
        Servidor.encolar(sesion, "/oauth/device/code/", #"{"detail":"not found"}"#, estado: 404)

        await #expect(throws: FlujoDeDispositivo.Falla.servidorNoSoportaElFlujo) {
            _ = try await flujo(sesion).solicitarCodigo()
        }
    }

    /// Las rutas de Sentry terminan en barra y NO redirigen si falta: devuelven 404 seco
    /// (medido contra sentry.io). Si alguien "limpia" las barras finales, la aplicación deja de
    /// funcionar entera y el error no dice nada sobre barras.
    @Test("Las rutas mantienen la barra final")
    func barraFinal() async throws {
        let sesion = Servidor.sesion()
        Servidor.encolar(sesion, "/oauth/device/code/", codigoOK)
        _ = try await flujo(sesion).solicitarCodigo()
        let url = try #require(Servidor.peticiones(sesion).first?.ruta)
        #expect(url.hasSuffix("/oauth/device/code/"))
    }

    @Test("Sin identificador de cliente no se sale a la red siquiera")
    func sinCliente() async {
        let sesion = Servidor.sesion()
        let sinID = FlujoDeDispositivo(host: URL(string: "https://x")!, clientID: "", sesion: sesion)
        await #expect(throws: FlujoDeDispositivo.Falla.clienteNoConfigurado) {
            _ = try await sinID.solicitarCodigo()
        }
        #expect(Servidor.peticiones(sesion).isEmpty)
    }

    @Test("Se renueva bajo el 10 % de vida restante, no antes")
    func cuandoRefrescar() {
        let ahora = Date(timeIntervalSince1970: 1_000_000)
        let vida: TimeInterval = 3600
        #expect(!FlujoDeDispositivo.convieneRefrescar(vence: ahora.addingTimeInterval(600), vida: vida, ahora: ahora))
        #expect(FlujoDeDispositivo.convieneRefrescar(vence: ahora.addingTimeInterval(300), vida: vida, ahora: ahora))
        #expect(FlujoDeDispositivo.convieneRefrescar(vence: ahora.addingTimeInterval(-1), vida: vida, ahora: ahora))
    }
}
