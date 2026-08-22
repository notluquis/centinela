import Foundation

public enum ErrorDeSentry: LocalizedError, Sendable {
    case sinCredenciales
    case noAutorizado
    case sinPermiso(String)
    case limiteDePeticiones(reintentarEn: TimeInterval?)
    case http(Int)
    case respuestaInesperada(String)

    public var errorDescription: String? {
        switch self {
        case .sinCredenciales:
            "Falta el token. Ábrelo en Ajustes y pega uno de sólo lectura."
        case .noAutorizado:
            "Sentry rechazó el token (401). Puede estar revocado o vencido."
        case .sinPermiso(let detalle):
            "El token no tiene permiso para esto: \(detalle)"
        case .limiteDePeticiones(let espera):
            espera.map { "Sentry limitó las peticiones. Reintento en \(Int($0))s." }
                ?? "Sentry limitó las peticiones."
        case .http(let codigo):
            "Sentry respondió \(codigo)."
        case .respuestaInesperada(let que):
            "Respuesta inesperada de Sentry: \(que)"
        }
    }
}

public struct Credenciales: Sendable, Equatable {
    public var token: String
    public var organizacion: String
    public var host: URL

    public init(token: String, organizacion: String, host: URL = URL(string: "https://sentry.io")!) {
        self.token = token
        self.organizacion = organizacion
        self.host = host
    }
}

/// Aviso de que una ruta que usamos quedó deprecada.
///
/// Sentry publica una política de deprecación: cuando una ruta entra en cuenta regresiva, sus
/// respuestas empiezan a traer `X-Sentry-Deprecation-Date` y, si existe reemplazo,
/// `X-Sentry-Replacement-Endpoint`. Ignorar esos encabezados es cómo una aplicación se entera
/// de un cambio el día que deja de funcionar, con un error que no menciona la deprecación.
///
/// Al 2026-08-22 ninguna de las cinco rutas que Centinela usa trae estos encabezados.
public struct AvisoDeDeprecacion: Sendable, Equatable {
    public let ruta: String
    public let fecha: String
    public let reemplazo: String?
}

public struct ClienteDeSentry: Sendable {
    private let credenciales: Credenciales
    private let sesion: URLSession
    /// Se llama cuando una respuesta trae los encabezados de deprecación de Sentry.
    private let alDeprecar: (@Sendable (AvisoDeDeprecacion) -> Void)?

    public init(
        credenciales: Credenciales,
        sesion: URLSession? = nil,
        alDeprecar: (@Sendable (AvisoDeDeprecacion) -> Void)? = nil
    ) {
        self.credenciales = credenciales
        self.alDeprecar = alDeprecar
        if let sesion {
            self.sesion = sesion
        } else {
            let conf = URLSessionConfiguration.ephemeral
            // Efímera a propósito: sin caché en disco, sin cookies, sin credenciales
            // persistidas. Los títulos de los incidencias pueden traer datos del negocio y no
            // tienen por qué quedar escritos en ninguna parte del disco.
            conf.httpShouldSetCookies = false
            conf.httpCookieAcceptPolicy = .never
            conf.urlCache = nil
            conf.requestCachePolicy = .reloadIgnoringLocalCacheData
            conf.timeoutIntervalForRequest = 20
            // `waitsForConnectivity` va en FALSE a propósito, y esto salió de leer la
            // documentación, no de verlo fallar: cuando está en `true`, una petición sin red no
            // falla, se queda esperando hasta `timeoutIntervalForResource`, cuyo valor por
            // omisión es de SIETE DÍAS. En un sondeo cada cinco minutos eso significa tareas
            // apilándose en silencio y un panel que nunca dice que no hay red. Acá lo correcto
            // es fallar rápido: el ciclo siguiente vuelve a intentar en minutos.
            conf.waitsForConnectivity = false
            conf.timeoutIntervalForResource = 60
            self.sesion = URLSession(configuration: conf)
        }
    }

    // MARK: - Decodificación

    /// Sentry mezcla dos formatos ISO-8601 en la MISMA respuesta: `lastSeen` de una incidencia llega
    /// como `2026-08-22T18:09:56Z` y `dateCreated` de un release como
    /// `2026-08-22T18:15:40.781127Z`. `.iso8601` a secas revienta con el segundo, y
    /// `.withFractionalSeconds` revienta con el primero. Por eso se prueban los dos.
    static let decodificador: JSONDecoder = {
        let con = ISO8601DateFormatter()
        con.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let sin = ISO8601DateFormatter()
        sin.formatOptions = [.withInternetDateTime]

        let decodificador = JSONDecoder()
        decodificador.dateDecodingStrategy = .custom { decodificador in
            let texto = try decodificador.singleValueContainer().decode(String.self)
            if let fecha = con.date(from: texto) ?? sin.date(from: texto) { return fecha }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decodificador.codingPath, debugDescription: "fecha no ISO-8601: \(texto)")
            )
        }
        return decodificador
    }()

    // MARK: - Transporte

    private func pedir(_ ruta: String, _ consulta: [URLQueryItem]) async throws -> Data {
        guard !credenciales.organizacion.isEmpty else { throw ErrorDeSentry.sinCredenciales }
        let completa = "api/0/organizations/\(credenciales.organizacion)/\(ruta)/"
        return try await pedirEnRuta(completa, consulta)
    }

    /// Igual que `pedir`, pero con la ruta completa: hay endpoints que NO cuelgan de una
    /// organización, y `organizations/` es justamente el que hace falta para saber cuál es.
    private func pedirEnRuta(_ ruta: String, _ consulta: [URLQueryItem]) async throws -> Data {
        guard !credenciales.token.isEmpty else { throw ErrorDeSentry.sinCredenciales }
        // La barra final NO es cosmética: `…/projects` sin ella devuelve 404 seco, sin
        // redirección (medido contra sentry.io). `appendingPathComponent` la conserva; cambiar
        // esta línea por algo que la coma rompe la aplicación entera con un error que no
        // menciona barras por ningún lado.
        var componentes = URLComponents(
            url: credenciales.host.appendingPathComponent(ruta),
            resolvingAgainstBaseURL: false
        )!
        // Sólo si hay algo: asignar un arreglo vacío deja la URL terminada en `?` suelto
        // (`…/organizations/?`). Sentry lo tolera, pero es basura que después aparece en logs
        // ajenos y en cualquier comparación de URLs.
        if !consulta.isEmpty { componentes.queryItems = consulta }

        var peticion = URLRequest(url: componentes.url!)
        peticion.setValue("Bearer \(credenciales.token)", forHTTPHeaderField: "Authorization")
        // URLSession ya negocia gzip por su cuenta y Sentry lo respeta (medido: la respuesta
        // de incidencias llega comprimida). No hay ETag en ninguna ruta de la API, así que no
        // existe revalidación condicional que aprovechar: lo liviano sale de pedir poco.
        peticion.setValue("centinela", forHTTPHeaderField: "User-Agent")

        let (datos, respuesta) = try await sesion.data(for: peticion)
        guard let http = respuesta as? HTTPURLResponse else {
            throw ErrorDeSentry.respuestaInesperada("respuesta sin estado HTTP")
        }
        if let aviso = Self.deprecacion(en: http, ruta: ruta) { alDeprecar?(aviso) }
        switch http.statusCode {
        case 200...299:
            return datos
        case 401:
            throw ErrorDeSentry.noAutorizado
        case 403:
            let detalle = (try? JSONSerialization.jsonObject(with: datos) as? [String: Any])?["detail"] as? String
            throw ErrorDeSentry.sinPermiso(detalle ?? "403")
        case 429:
            let espera = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw ErrorDeSentry.limiteDePeticiones(reintentarEn: espera)
        default:
            throw ErrorDeSentry.http(http.statusCode)
        }
    }

    private func pedir<T: Decodable>(_ tipo: T.Type, _ ruta: String, _ consulta: [URLQueryItem]) async throws -> T {
        try await decodificar(tipo, try await pedir(ruta, consulta), ruta: ruta)
    }

    private func decodificar<T: Decodable>(_ tipo: T.Type, _ datos: Data, ruta: String) async throws -> T {
        do {
            return try Self.decodificador.decode(T.self, from: datos)
        } catch {
            throw ErrorDeSentry.respuestaInesperada("\(ruta): \(error)")
        }
    }

    /// Las organizaciones a las que llega el token. NO cuelga de una organización, por eso pasa
    /// por `pedirEnRuta`.
    ///
    /// Existe para cerrar un agujero del inicio de sesión: el flujo de dispositivo entrega un
    /// token y nada más. Sin esto, alguien iniciaba sesión con éxito y la aplicación seguía
    /// diciendo "Falta configurar", porque `organizacion` seguía vacía y ninguna capa reportaba
    /// error.
    public func organizaciones() async throws -> [Organizacion] {
        let datos = try await pedirEnRuta("api/0/organizations/", [])
        return try await decodificar([Organizacion].self, datos, ruta: "organizations")
    }

    /// Lee los encabezados de la política de deprecación de Sentry. `internal` para que la
    /// suite pueda ejercitarla sin salir a la red.
    static func deprecacion(en http: HTTPURLResponse, ruta: String) -> AvisoDeDeprecacion? {
        guard let fecha = http.value(forHTTPHeaderField: "X-Sentry-Deprecation-Date") else { return nil }
        return AvisoDeDeprecacion(
            ruta: ruta,
            fecha: fecha,
            reemplazo: http.value(forHTTPHeaderField: "X-Sentry-Replacement-Endpoint")
        )
    }

    // MARK: - Lo barato: esto es lo que se pide en cada ciclo

    /// 378 ms y 937 B medidos contra una organización real: 3 veces más rápido y 11 veces más
    /// liviano que pedir la lista de incidencias. Es lo que alimenta el número y la chispa.
    public func serieDeErrores(ventana: Ventana, intervalo: String = "1h") async throws -> SerieDeEventos {
        let datos = try await pedir("events-stats", [
            .init(name: "statsPeriod", value: ventana.rawValue),
            .init(name: "interval", value: intervalo),
            .init(name: "yAxis", value: "count()"),
            .init(name: "query", value: "event.type:error"),
            .init(name: "project", value: "-1")
        ])
        return try SerieDeEventos(json: datos)
    }

    /// 490 ms medidos. Devuelve la configuración de los monitores, no su historia.
    public func monitoresDeUptime() async throws -> [MonitorDeUptime] {
        try await pedir([MonitorDeUptime].self, "uptime", [])
    }

    // MARK: - Lo caro: sólo al abrir el panel

    /// 1047 ms y 10,6 KB medidos: la ruta más cara de la API. Por eso no va en el ciclo
    /// periódico: se pide cuando alguien abre el panel y quiere leer los títulos.
    public func issuesSinResolver(ventana: Ventana, limite: Int = 15) async throws -> [Incidencia] {
        try await pedir([Incidencia].self, "incidencias", [
            .init(name: "query", value: "is:unresolved"),
            .init(name: "statsPeriod", value: ventana.rawValue),
            .init(name: "limit", value: String(limite)),
            .init(name: "project", value: "-1")
        ])
    }

    public func issuesPorRevisar(ventana: Ventana = .catorceDias, limite: Int = 10) async throws -> [Incidencia] {
        try await pedir([Incidencia].self, "incidencias", [
            .init(name: "query", value: "is:unresolved is:for_review"),
            .init(name: "statsPeriod", value: ventana.rawValue),
            .init(name: "limit", value: String(limite)),
            .init(name: "project", value: "-1")
        ])
    }

    public func ultimosReleases(limite: Int = 5) async throws -> [Release] {
        try await pedir([Release].self, "releases", [.init(name: "per_page", value: String(limite))])
    }

    public func proyectos() async throws -> [Proyecto] {
        try await pedir([Proyecto].self, "projects", [])
    }

    // MARK: - Higiene del token

    /// Un token de sólo lectura NO puede leer la bitácora de auditoría de la organización.
    /// Si esta llamada devuelve 200, el token trae permisos de escritura y el widget está
    /// corriendo con más poder del que necesita: se avisa en la interfaz.
    ///
    /// Existe porque el primer token que se usó acá era el de `sentry-cli` (el mismo que sube
    /// sourcemaps y publica releases) y leía la auditoría sin problema.
    public func tokenPareceDeSoloLectura() async -> Bool {
        do {
            _ = try await pedir("audit-logs", [.init(name: "per_page", value: "1")])
            return false
        } catch ErrorDeSentry.sinPermiso, ErrorDeSentry.http(404) {
            return true
        } catch {
            // Un fallo de red no dice nada del token: no se acusa sin evidencia.
            return true
        }
    }
}

public enum Ventana: String, CaseIterable, Sendable {
    case unaHora = "1h"
    case seisHoras = "6h"
    case veinticuatroHoras = "24h"
    case sieteDias = "7d"
    case catorceDias = "14d"

    public var etiqueta: String {
        switch self {
        case .unaHora: "1 hora"
        case .seisHoras: "6 horas"
        case .veinticuatroHoras: "24 horas"
        case .sieteDias: "7 días"
        case .catorceDias: "14 días"
        }
    }
}
