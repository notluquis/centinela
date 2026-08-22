import Foundation

// Los campos de acá salen de mirar respuestas reales de la API, no de la documentación.
// Los tres que sorprenden están comentados en el sitio donde muerden.

public struct Organizacion: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let slug: String
    public let name: String
}

public struct Proyecto: Codable, Sendable, Hashable {
    public let id: String
    public let slug: String
    public let name: String
}

/// Un issue de Sentry.
///
/// Se llama `Incidencia` y no `Issue` por una razón concreta: Swift Testing exporta su propio
/// `Testing.Issue`, y en cualquier archivo de tests con `import Testing` el nombre corto se
/// resuelve al de ellos. El síntoma no dice nada: el compilador emite
/// `failed to produce diagnostic for expression` sobre la llamada a `decode`, sin mencionar la
/// ambigüedad, y se pierde un buen rato buscando el error en el `Codable`.
public struct Incidencia: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let shortId: String
    public let title: String
    public let culprit: String?
    public let level: String?
    public let substatus: String?
    public let permalink: URL
    public let lastSeen: Date
    public let userCount: Int
    public let project: Proyecto
    public let isUnhandled: Bool?

    /// Sentry devuelve el conteo de eventos como **texto** (`"13"`), no como número, mientras
    /// que `userCount` sí llega como entero. Decodificarlo como `Int` falla con
    /// `typeMismatch` y se lleva la lista completa, no sólo ese campo.
    public let count: Int

    enum CodingKeys: String, CodingKey {
        case id, shortId, title, culprit, level, substatus, permalink, lastSeen
        case userCount, project, isUnhandled, count
    }

    public init(from decoder: any Decoder) throws {
        let cont = try decoder.container(keyedBy: CodingKeys.self)
        id = try cont.decode(String.self, forKey: .id)
        shortId = try cont.decode(String.self, forKey: .shortId)
        title = try cont.decode(String.self, forKey: .title)
        culprit = try cont.decodeIfPresent(String.self, forKey: .culprit)
        level = try cont.decodeIfPresent(String.self, forKey: .level)
        substatus = try cont.decodeIfPresent(String.self, forKey: .substatus)
        permalink = try cont.decode(URL.self, forKey: .permalink)
        lastSeen = try cont.decode(Date.self, forKey: .lastSeen)
        userCount = try cont.decodeIfPresent(Int.self, forKey: .userCount) ?? 0
        project = try cont.decode(Proyecto.self, forKey: .project)
        isUnhandled = try cont.decodeIfPresent(Bool.self, forKey: .isUnhandled)
        count = Int(try cont.decode(String.self, forKey: .count)) ?? 0
    }

    public func encode(to encoder: any Encoder) throws {
        var cont = encoder.container(keyedBy: CodingKeys.self)
        try cont.encode(id, forKey: .id)
        try cont.encode(shortId, forKey: .shortId)
        try cont.encode(title, forKey: .title)
        try cont.encodeIfPresent(culprit, forKey: .culprit)
        try cont.encodeIfPresent(level, forKey: .level)
        try cont.encodeIfPresent(substatus, forKey: .substatus)
        try cont.encode(permalink, forKey: .permalink)
        try cont.encode(lastSeen, forKey: .lastSeen)
        try cont.encode(userCount, forKey: .userCount)
        try cont.encode(project, forKey: .project)
        try cont.encodeIfPresent(isUnhandled, forKey: .isUnhandled)
        try cont.encode(String(count), forKey: .count)
    }

    public var severidad: Severidad { Severidad(textoDeSentry: level) }
}

public enum Severidad: String, Sendable {
    case fatal, error, warning, info, debug, sample

    init(textoDeSentry texto: String?) {
        self = Severidad(rawValue: texto ?? "") ?? .error
    }

    /// Nombre de SF Symbol. `NSImage(systemSymbolName:)` devuelve `nil` con un nombre que no
    /// existe, así que sólo se usan símbolos presentes desde macOS 11.
    public var simbolo: String {
        switch self {
        case .fatal: "flame.fill"
        case .error: "exclamationmark.triangle.fill"
        case .warning: "exclamationmark.circle.fill"
        case .info, .debug, .sample: "info.circle"
        }
    }
}

public struct Release: Codable, Sendable, Identifiable, Hashable {
    public let version: String
    public let shortVersion: String
    public let dateCreated: Date
    public let newGroups: Int

    public var id: String { version }

    /// La API devuelve el SHA completo tanto en `version` como en `shortVersion` cuando el
    /// release se nombró con un SHA, así que acortar es cosa nuestra.
    public var etiqueta: String {
        let texto = shortVersion
        let pareceSHA = texto.count == 40 && texto.allSatisfy(\.isHexDigit)
        return pareceSHA ? String(texto.prefix(7)) : texto
    }
}

public struct MonitorDeUptime: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let url: URL
    public let status: String
    public let intervalSeconds: Int

    /// Entero, no texto ni booleano. Sólo se ha observado `1` en un monitor sano; el resto se
    /// trata como "no sano" en vez de adivinar la tabla completa, que la API no documenta.
    public let uptimeStatus: Int

    public var sano: Bool { uptimeStatus == 1 }
    public var activo: Bool { status == "active" }
}

/// Serie temporal de `events-stats`. La respuesta viene como pares heterogéneos
/// `[epoch, [{"count": n}]]`, que no es un objeto y por eso no hay `Codable` sintetizable.
public struct SerieDeEventos: Sendable, Hashable {
    public struct Punto: Sendable, Hashable {
        public let instante: Date
        public let cantidad: Int
    }

    public let puntos: [Punto]

    public var total: Int { puntos.reduce(0) { $0 + $1.cantidad } }

    public init(puntos: [Punto]) { self.puntos = puntos }

    public init(json: Data) throws {
        guard
            let raiz = try JSONSerialization.jsonObject(with: json) as? [String: Any],
            let filas = raiz["data"] as? [[Any]]
        else { throw ErrorDeSentry.respuestaInesperada("events-stats sin arreglo `data`") }

        puntos = filas.compactMap { fila in
            guard fila.count >= 2, let epoch = fila[0] as? TimeInterval else { return nil }
            let cubetas = fila[1] as? [[String: Any]] ?? []
            let cantidad = cubetas.reduce(0) { $0 + (($1["count"] as? NSNumber)?.intValue ?? 0) }
            return Punto(instante: Date(timeIntervalSince1970: epoch), cantidad: cantidad)
        }
    }
}
