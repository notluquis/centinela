import Foundation
import Testing

@testable import CentinelaCore

/// Cada test de acá fija una forma REAL de la respuesta de Sentry que ya rompió algo, o que
/// rompería si alguien "simplificara" el decodificador. Las fixtures están anonimizadas: los
/// títulos de incidencias reales traen URLs y datos del negocio, y este repositorio es público.
///
/// Se usa Swift Testing y no XCTest por dos motivos que apuntan al mismo lado: es el marco por
/// omisión desde 2026, y `XCTest` **no viene** en una toolchain de swiftly (sólo con Xcode),
/// así que con XCTest la suite no correría en una máquina sin Xcode, que es justo el flujo que
/// este proyecto documenta.
@Suite("Decodificación de las respuestas de Sentry")
struct DecodificacionTests {
    private func fixture(_ nombre: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: nombre, withExtension: "json", subdirectory: "Fixtures"),
            "falta la fixture \(nombre).json"
        )
        return try Data(contentsOf: url)
    }

    /// Sentry manda el conteo de eventos como texto (`"13"`) y el de personas como número.
    /// Declarar `count` como `Int` hace que el arreglo COMPLETO falle con `typeMismatch`, no
    /// sólo ese campo.
    @Test("El conteo llega como texto y se decodifica como número")
    func conteoComoTexto() throws {
        let datosissues = try fixture("incidencias")
        let incidencias = try ClienteDeSentry.decodificador.decode([Incidencia].self, from: datosissues)
        #expect(incidencias.count == 2)
        #expect(incidencias[0].count == 13)
        #expect(incidencias[0].userCount == 3)
    }

    /// Dos formatos ISO-8601 en la misma respuesta: uno con fracción de segundo y otro sin.
    /// `.iso8601` a secas falla con el primero; `.withFractionalSeconds` falla con el segundo.
    @Test("Convive fecha con fracción de segundo y sin ella")
    func dosFormatosDeFecha() throws {
        let datosissues = try fixture("incidencias")
        let incidencias = try ClienteDeSentry.decodificador.decode([Incidencia].self, from: datosissues)
        #expect(incidencias[0].lastSeen.timeIntervalSince1970 == 1_787_422_196)
        // `.123` y no `.123456`: `ISO8601DateFormatter` con `.withFractionalSeconds` trunca a
        // milisegundos, y Sentry manda microsegundos. Da igual para lo que hace esta aplicación
        // (ordenar y mostrar "hace 3 minutos"), pero quien compare fechas al microsegundo contra
        // la API se va a preguntar dónde se perdieron.
        #expect(abs(incidencias[1].lastSeen.timeIntervalSince1970 - 1_787_418_000.123456) < 0.001)

        let datosreleases = try fixture("releases")
        let releases = try ClienteDeSentry.decodificador.decode([Release].self, from: datosreleases)
        #expect(releases.count == 2)
    }

    @Test("Los campos opcionales ausentes no tumban la lista")
    func opcionalesAusentes() throws {
        let datosissues = try fixture("incidencias")
        let incidencias = try ClienteDeSentry.decodificador.decode([Incidencia].self, from: datosissues)
        #expect(incidencias[1].culprit == nil)
        #expect(incidencias[1].substatus == nil)
        #expect(incidencias[1].isUnhandled == nil)
    }

    /// `events-stats` devuelve pares heterogéneos `[epoch, [{"count": n}]]`, que no son un
    /// objeto y por eso no hay `Codable` que se sintetice solo. El cuarto punto trae la lista
    /// de cubetas vacía, que es lo que manda cuando no hubo eventos en ese intervalo.
    @Test("La serie de eventos sale de pares heterogéneos")
    func serieDeEventos() throws {
        let serie = try SerieDeEventos(json: fixture("events-stats"))
        #expect(serie.puntos.map(\.cantidad) == [0, 1, 4, 0])
        #expect(serie.total == 5)
        #expect(serie.puntos[0].instante.timeIntervalSince1970 == 1_787_335_200)
    }

    @Test("Una respuesta sin `data` falla ruidosa, no devuelve una serie vacía")
    func serieSinData() {
        #expect(throws: ErrorDeSentry.self) {
            try SerieDeEventos(json: Data(#"{"meta": {}}"#.utf8))
        }
    }

    @Test("El estado de uptime es entero, no booleano")
    func uptimeEsEntero() throws {
        let datosmonitores = try fixture("uptime")
        let monitores = try ClienteDeSentry.decodificador.decode([MonitorDeUptime].self, from: datosmonitores)
        #expect(monitores[0].sano)
        #expect(!monitores[1].sano)
        let todosActivos = monitores.allSatisfy(\.activo)
        #expect(todosActivos)
    }

    /// Cuando el release se nombró con un SHA, la API repite el SHA de 40 caracteres en
    /// `shortVersion`: acortar es cosa nuestra. Una versión semántica no se toca.
    @Test("El SHA se acorta y la versión semántica no")
    func etiquetaDeRelease() throws {
        let datosreleases = try fixture("releases")
        let releases = try ClienteDeSentry.decodificador.decode([Release].self, from: datosreleases)
        #expect(releases[0].etiqueta == "fa907c0")
        #expect(releases[1].etiqueta == "v2.4.1")
    }

    @Test("Un nivel desconocido no rompe y cae en error", arguments: [
        ("warning", Severidad.warning),
        ("fatal", Severidad.fatal),
        ("algo-que-sentry-invente-manana", Severidad.error)
    ])
    func nivelDesconocido(texto: String, esperado: Severidad) {
        #expect(Severidad(textoDeSentry: texto) == esperado)
    }

    @Test("Un nivel ausente también cae en error")
    func nivelAusente() {
        #expect(Severidad(textoDeSentry: nil) == .error)
    }
}

/// Sentry publica una política de deprecación por encabezados. Una aplicación que los ignora se
/// entera del cambio el día que deja de funcionar.
@Suite("Política de deprecación de Sentry")
struct DeprecacionTests {
    // La URL sale a una constante: anidar un `#require` dentro de otro hace que el
    // compilador reviente con "recursive expansion of macro".
    private static let url = URL(string: "https://sentry.io/api/0/organizations/x/issues/")

    private func respuesta(_ campos: [String: String]) throws -> HTTPURLResponse {
        let url = try #require(Self.url)
        return try #require(HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: campos
        ))
    }

    @Test("Sin los encabezados no hay aviso")
    func sinAviso() throws {
        let http = try respuesta(["Content-Type": "application/json"])
        #expect(ClienteDeSentry.deprecacion(en: http, ruta: "issues") == nil)
    }

    @Test("Con fecha y reemplazo se arma el aviso completo")
    func avisoCompleto() throws {
        let http = try respuesta([
            "X-Sentry-Deprecation-Date": "2027-01-01",
            "X-Sentry-Replacement-Endpoint": "/organizations/{org}/otra-cosa/"
        ])
        let aviso = try #require(ClienteDeSentry.deprecacion(en: http, ruta: "issues"))
        #expect(aviso.fecha == "2027-01-01")
        #expect(aviso.reemplazo == "/organizations/{org}/otra-cosa/")
    }

    /// El reemplazo es opcional en la política: hay rutas que se retiran sin sucesora. Exigirlo
    /// haría que el aviso más importante, el que no tiene salida, fuera el único que no se ve.
    @Test("Una fecha sin reemplazo igual avisa")
    func avisoSinReemplazo() throws {
        let http = try respuesta(["X-Sentry-Deprecation-Date": "2027-01-01"])
        let aviso = try #require(ClienteDeSentry.deprecacion(en: http, ruta: "uptime"))
        #expect(aviso.reemplazo == nil)
    }
}

/// El flujo de dispositivo entrega un token y nada más. Para que la aplicación quede
/// configurada hay que preguntarle a Sentry a qué organizaciones llega ese token.
@Suite("Organizaciones")
struct OrganizacionesTests {
    private func cliente(_ sesion: URLSession, organizacion: String = "") -> ClienteDeSentry {
        ClienteDeSentry(
            credenciales: Credenciales(
                token: "token-de-prueba", organizacion: organizacion,
                host: URL(string: "https://sentry.example")!
            ),
            sesion: sesion
        )
    }

    /// La ruta NO lleva prefijo de organización: pedirla con uno da 404, y ese es justo el
    /// endpoint que se usa cuando todavía no se sabe cuál es la organización.
    @Test("Se pide a /api/0/organizations/, sin prefijo de organización")
    func rutaSinPrefijo() async throws {
        let sesion = Servidor.sesion()
        Servidor.encolar(sesion, "/api/0/organizations/", "[]")
        _ = try await cliente(sesion).organizaciones()
        let pedida = try #require(Servidor.peticiones(sesion).first?.ruta)
        #expect(pedida.hasSuffix("/api/0/organizations/"))
        #expect(!pedida.contains("/organizations//"))
    }

    @Test("Se decodifican slug y nombre")
    func decodifica() async throws {
        let sesion = Servidor.sesion()
        let cuerpo = #"[{"id":"1","slug":"ejemplo","name":"Ejemplo SpA"}]"#
        Servidor.encolar(sesion, "/api/0/organizations/", cuerpo)
        let organizaciones = try await cliente(sesion).organizaciones()
        #expect(organizaciones.map(\.slug) == ["ejemplo"])
        #expect(organizaciones[0].name == "Ejemplo SpA")
    }

    /// Sin token no se sale a la red. Sin organización sí, que es la diferencia entre esta
    /// ruta y todas las demás.
    @Test("Sin token falla antes de pedir; sin organización no")
    func credencialesMinimas() async {
        let sesion = Servidor.sesion()
        let sinToken = ClienteDeSentry(
            credenciales: Credenciales(token: "", organizacion: "", host: URL(string: "https://x")!),
            sesion: sesion
        )
        await #expect(throws: ErrorDeSentry.self) { _ = try await sinToken.organizaciones() }
        #expect(Servidor.peticiones(sesion).isEmpty)
    }
}
