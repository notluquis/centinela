import Foundation
import Testing

@testable import CentinelaCore

/// Estos son los tests de integración del proyecto: ejercitan el flujo COMPLETO de inicio de
/// sesión contra un servidor de mentira, incluida la espera y el reintento.
///
/// Un `XCUITest` de verdad no es posible acá: XCUITest viene con Xcode y este proyecto se
/// construye con la toolchain suelta. Interceptar el transporte a nivel de `URLProtocol` es lo
/// más lejos que se llega sin Xcode, y alcanza para lo que de verdad puede fallar: el orden de
/// los pasos, los cuatro errores del RFC 8628 y la rotación del token de refresco.
// `.serialized` no es decoración: Swift Testing corre en paralelo por omisión y `URLProtocol`
// se registra por proceso, así que sin esto los tests se roban las respuestas encoladas entre
// ellos y fallan con "sin respuesta encolada". El comentario de arriba decía que la suite iba
// en serie antes de que efectivamente lo fuera.
@Suite("Flujo de dispositivo (OAuth 2.0, RFC 8628)", .serialized)
struct FlujoDeDispositivoTests {
    // MARK: - Servidor de mentira

    /// Respuestas encoladas por ruta. `URLProtocol` se registra por proceso, así que la suite va
    /// en serie y cada test limpia lo suyo.
    final class Servidor: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var respuestas: [(ruta: String, estado: Int, cuerpo: String)] = []
        nonisolated(unsafe) static var peticiones: [(ruta: String, cuerpo: String)] = []

        static func encolar(_ ruta: String, _ cuerpo: String, estado: Int = 200) {
            respuestas.append((ruta, estado, cuerpo))
        }

        static func limpiar() {
            respuestas.removeAll()
            peticiones.removeAll()
        }

        static func sesion() -> URLSession {
            let conf = URLSessionConfiguration.ephemeral
            conf.protocolClasses = [Servidor.self]
            return URLSession(configuration: conf)
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func stopLoading() {}

        override func startLoading() {
            // `URL.path` DESCARTA la barra final, y las rutas de Sentry la llevan
            // (`/oauth/device/code/`). Comparar por `path` hacía que nada calzara y todos los
            // tests fallaran con "sin respuesta encolada", como si el stub no existiera.
            let ruta = request.url?.absoluteString ?? ""
            // `httpBody` viene vacío cuando URLSession ya subió el cuerpo a un stream; se lee de
            // ahí, que es lo que pasa con los POST de formulario.
            let cuerpoEnviado = request.httpBody.map { String(decoding: $0, as: UTF8.self) }
                ?? request.httpBodyStream.map { flujo in
                    flujo.open()
                    defer { flujo.close() }
                    var datos = Data()
                    var buffer = [UInt8](repeating: 0, count: 4096)
                    while flujo.hasBytesAvailable {
                        let n = flujo.read(&buffer, maxLength: buffer.count)
                        if n <= 0 { break }
                        datos.append(buffer, count: n)
                    }
                    return String(decoding: datos, as: UTF8.self)
                } ?? ""
            Servidor.peticiones.append((ruta, cuerpoEnviado))

            let indice = Servidor.respuestas.firstIndex { ruta.contains($0.ruta) }
            let elegida = indice.map { Servidor.respuestas.remove(at: $0) }
                ?? (ruta: ruta, estado: 500, cuerpo: #"{"error":"sin respuesta encolada"}"#)

            let http = HTTPURLResponse(
                url: request.url!, statusCode: elegida.estado,
                httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(elegida.cuerpo.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    private func flujo() -> FlujoDeDispositivo {
        FlujoDeDispositivo(
            host: URL(string: "https://sentry.example")!,
            clientID: "cliente-de-prueba",
            sesion: Servidor.sesion()
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
        Servidor.limpiar()
        defer { Servidor.limpiar() }
        Servidor.encolar("/oauth/device/code/", codigoOK)

        let codigo = try await flujo().solicitarCodigo()
        #expect(codigo.userCode == "ABCD-EFGH")
        #expect(codigo.deviceCode == "DEV-1")
        #expect(codigo.urlCompleta?.absoluteString.contains("ABCD-EFGH") == true)
        #expect(codigo.intervalo == 5)

        // Los permisos que se piden son parte del contrato con el usuario: si alguien agrega
        // `project:write` acá, el diálogo de Sentry se lo pide y este test se pone rojo.
        let enviado = try #require(Servidor.peticiones.first?.cuerpo)
        // Los dos puntos no se codifican (son válidos en una consulta) y el espacio va como
        // `%20`, que Django acepta igual que `+`.
        #expect(enviado.contains("scope=org:read%20project:read%20event:read"))
        #expect(!enviado.contains("write"))
    }

    @Test("Se espera mientras la persona no aprueba, y al aprobar devuelve el token")
    func esperaYAprobacion() async throws {
        Servidor.limpiar()
        defer { Servidor.limpiar() }
        Servidor.encolar("/oauth/token/", #"{"error":"authorization_pending"}"#)
        Servidor.encolar("/oauth/token/", #"{"error":"authorization_pending"}"#)
        Servidor.encolar("/oauth/token/", #"{"access_token":"AT-1","refresh_token":"RT-1","expires_in":3600}"#)

        let codigo = FlujoDeDispositivo.Codigo(
            deviceCode: "DEV-1", userCode: "X", urlDeVerificacion: URL(string: "https://x")!,
            urlCompleta: nil, expiraEn: 600, intervalo: 5
        )
        var esperas: [TimeInterval] = []
        let concesion = try await flujo().esperarAutorizacion(codigo) { esperas.append($0) }

        #expect(concesion.tokenDeAcceso == "AT-1")
        #expect(concesion.tokenDeRefresco == "RT-1")
        #expect(esperas == [5, 5, 5])
    }

    /// El RFC 8628 obliga a subir el intervalo 5 segundos cada vez que llega `slow_down`.
    /// Ignorarlo deja al cliente preguntando al mismo ritmo y el servidor sigue rechazando.
    @Test("`slow_down` sube el intervalo y no se queda pegado")
    func slowDown() async throws {
        Servidor.limpiar()
        defer { Servidor.limpiar() }
        Servidor.encolar("/oauth/token/", #"{"error":"slow_down"}"#)
        Servidor.encolar("/oauth/token/", #"{"error":"slow_down"}"#)
        Servidor.encolar("/oauth/token/", #"{"access_token":"AT","expires_in":60}"#)

        let codigo = FlujoDeDispositivo.Codigo(
            deviceCode: "D", userCode: "X", urlDeVerificacion: URL(string: "https://x")!,
            urlCompleta: nil, expiraEn: 600, intervalo: 5
        )
        var esperas: [TimeInterval] = []
        _ = try await flujo().esperarAutorizacion(codigo) { esperas.append($0) }
        #expect(esperas == [5, 10, 15])
    }

    @Test("Los dos finales malos del RFC llegan como errores distintos", arguments: [
        (#"{"error":"access_denied"}"#, FlujoDeDispositivo.Falla.rechazadoPorLaPersona),
        (#"{"error":"expired_token"}"#, FlujoDeDispositivo.Falla.codigoVencido),
    ])
    func finalesMalos(cuerpo: String, esperado: FlujoDeDispositivo.Falla) async {
        Servidor.limpiar()
        defer { Servidor.limpiar() }
        Servidor.encolar("/oauth/token/", cuerpo)

        let codigo = FlujoDeDispositivo.Codigo(
            deviceCode: "D", userCode: "X", urlDeVerificacion: URL(string: "https://x")!,
            urlCompleta: nil, expiraEn: 600, intervalo: 1
        )
        await #expect(throws: esperado) {
            _ = try await flujo().esperarAutorizacion(codigo) { _ in }
        }
    }

    /// Sentry rota el token de refresco, pero no siempre manda uno nuevo. Guardar `nil` a ciegas
    /// cierra la sesión en la renovación siguiente, y el usuario tiene que volver a entrar sin
    /// entender por qué.
    @Test("Refrescar sin token nuevo conserva el viejo")
    func refrescoConservaElToken() async throws {
        Servidor.limpiar()
        defer { Servidor.limpiar() }
        Servidor.encolar("/oauth/token/", #"{"access_token":"AT-2","expires_in":3600}"#)

        let concesion = try await flujo().refrescar("RT-VIEJO")
        #expect(concesion.tokenDeAcceso == "AT-2")
        #expect(concesion.tokenDeRefresco == "RT-VIEJO")
    }

    @Test("Refrescar con token nuevo se queda con el nuevo")
    func refrescoRota() async throws {
        Servidor.limpiar()
        defer { Servidor.limpiar() }
        Servidor.encolar("/oauth/token/", #"{"access_token":"AT-2","refresh_token":"RT-NUEVO","expires_in":3600}"#)

        let concesion = try await flujo().refrescar("RT-VIEJO")
        #expect(concesion.tokenDeRefresco == "RT-NUEVO")
    }

    /// Una instancia anterior a Sentry 26.1.0 no tiene el endpoint. Un 404 tiene que leerse como
    /// "este servidor no soporta el flujo", no como un error genérico: la salida del usuario es
    /// distinta (pegar un token a mano).
    @Test("Un 404 se traduce a «este servidor no soporta el flujo»")
    func servidorViejo() async {
        Servidor.limpiar()
        defer { Servidor.limpiar() }
        Servidor.encolar("/oauth/device/code/", #"{"detail":"not found"}"#, estado: 404)

        await #expect(throws: FlujoDeDispositivo.Falla.servidorNoSoportaElFlujo) {
            _ = try await flujo().solicitarCodigo()
        }
    }

    /// Las rutas de Sentry terminan en barra y NO redirigen si falta: devuelven 404 seco
    /// (medido contra sentry.io). Si alguien "limpia" las barras finales, la aplicación deja de
    /// funcionar entera y el error no dice nada sobre barras.
    @Test("Las rutas mantienen la barra final")
    func barraFinal() async throws {
        Servidor.limpiar()
        defer { Servidor.limpiar() }
        Servidor.encolar("/oauth/device/code/", codigoOK)
        _ = try await flujo().solicitarCodigo()
        let url = try #require(Servidor.peticiones.first?.ruta)
        #expect(url.hasSuffix("/oauth/device/code/"))
    }

    @Test("Sin identificador de cliente no se sale a la red siquiera")
    func sinCliente() async {
        Servidor.limpiar()
        defer { Servidor.limpiar() }
        let sinID = FlujoDeDispositivo(host: URL(string: "https://x")!, clientID: "", sesion: Servidor.sesion())
        await #expect(throws: FlujoDeDispositivo.Falla.clienteNoConfigurado) {
            _ = try await sinID.solicitarCodigo()
        }
        #expect(Servidor.peticiones.isEmpty)
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
