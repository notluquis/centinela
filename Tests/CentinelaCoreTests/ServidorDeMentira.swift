import Foundation

/// Una respuesta encolada en el servidor de mentira.
struct Respuesta {
    let ruta: String
    let estado: Int
    let cuerpo: String
}

/// Anota cuánto se durmió en cada vuelta del sondeo.
///
/// Es una clase con candado y no un `var` capturado por la clausura: `dormir` es `@Sendable`,
/// así que mutar un local desde adentro es una carrera. Hoy sale como aviso porque el paquete
/// está en modo de lenguaje 5; en modo 6 es un error, y el test tendría que reescribirse igual.
final class Cronometro: @unchecked Sendable {
    private let candado = NSLock()
    private var valores: [TimeInterval] = []

    func anotar(_ segundos: TimeInterval) {
        candado.lock()
        defer { candado.unlock() }
        valores.append(segundos)
    }

    var anotados: [TimeInterval] {
        candado.lock()
        defer { candado.unlock() }
        return valores
    }
}

/// Servidor HTTP de mentira, compartido por las suites que ejercitan el transporte: el flujo de
/// dispositivo y la búsqueda de actualizaciones.
///
/// **Cada sesión tiene su propia cola**, identificada por un encabezado que la configuración
/// inyecta en cada petición. La primera versión guardaba una cola global y `.serialized` en cada
/// suite: no alcanzaba, porque ese rasgo serializa DENTRO de una suite y no entre suites, así
/// que dos suites en paralelo se robaban las respuestas y fallaban con "sin respuesta encolada",
/// que no dice nada sobre el problema real.
final class Servidor: URLProtocol, @unchecked Sendable {
    private static let candado = NSLock()
    nonisolated(unsafe) private static var colas: [String: [Respuesta]] = [:]
    nonisolated(unsafe) private static var vistas: [String: [(ruta: String, cuerpo: String)]] = [:]
    nonisolated(unsafe) private static var siguienteID = 0

    static let encabezadoDeSesion = "X-Servidor-De-Mentira"

    /// Una sesión con cola propia. Se descarta sola al terminar el test que la creó.
    static func sesion() -> URLSession {
        candado.lock()
        siguienteID += 1
        let identificador = "sesion-\(siguienteID)"
        colas[identificador] = []
        vistas[identificador] = []
        candado.unlock()

        let conf = URLSessionConfiguration.ephemeral
        conf.protocolClasses = [Servidor.self]
        conf.httpAdditionalHeaders = [encabezadoDeSesion: identificador]
        return URLSession(configuration: conf)
    }

    static func encolar(_ sesion: URLSession, _ ruta: String, _ cuerpo: String, estado: Int = 200) {
        guard let identificador = identificador(de: sesion) else { return }
        candado.lock()
        defer { candado.unlock() }
        colas[identificador, default: []].append(Respuesta(ruta: ruta, estado: estado, cuerpo: cuerpo))
    }

    static func peticiones(_ sesion: URLSession) -> [(ruta: String, cuerpo: String)] {
        guard let identificador = identificador(de: sesion) else { return [] }
        candado.lock()
        defer { candado.unlock() }
        return vistas[identificador] ?? []
    }

    private static func identificador(de sesion: URLSession) -> String? {
        sesion.configuration.httpAdditionalHeaders?[encabezadoDeSesion] as? String
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        // `URL.path` DESCARTA la barra final, y las rutas de Sentry la llevan
        // (`/oauth/device/code/`). Comparar por `path` hacía que nada calzara.
        let ruta = request.url?.absoluteString ?? ""
        let identificador = request.value(forHTTPHeaderField: Servidor.encabezadoDeSesion) ?? ""
        let cuerpoEnviado = Servidor.cuerpo(de: request)

        Servidor.candado.lock()
        Servidor.vistas[identificador, default: []].append((ruta, cuerpoEnviado))
        let indice = Servidor.colas[identificador]?.firstIndex { ruta.contains($0.ruta) }
        let elegida = indice.map { Servidor.colas[identificador]!.remove(at: $0) }
            ?? Respuesta(ruta: ruta, estado: 500, cuerpo: #"{"error":"sin respuesta encolada"}"#)
        Servidor.candado.unlock()

        let http = HTTPURLResponse(
            url: request.url!, statusCode: elegida.estado,
            httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(elegida.cuerpo.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    /// `httpBody` viene vacío cuando URLSession ya subió el cuerpo a un stream, que es lo que
    /// pasa con los POST de formulario.
    private static func cuerpo(de request: URLRequest) -> String {
        if let datos = request.httpBody { return String(bytes: datos, encoding: .utf8) ?? "" }
        guard let flujo = request.httpBodyStream else { return "" }
        flujo.open()
        defer { flujo.close() }
        var datos = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while flujo.hasBytesAvailable {
            let leidos = flujo.read(&buffer, maxLength: buffer.count)
            if leidos <= 0 { break }
            datos.append(buffer, count: leidos)
        }
        return String(bytes: datos, encoding: .utf8) ?? ""
    }
}
