import Foundation
import Testing

@testable import CentinelaCore

@Suite("Comparación de versiones")
struct ActualizacionesTests {
    typealias Ver = BuscadorDeActualizaciones.Version

    @Test("Se lee con y sin la v de la etiqueta")
    func conYSinVer() throws {
        #expect(try #require(Ver("v1.2.3")).partes == [1, 2, 3])
        #expect(try #require(Ver("1.2.3")).partes == [1, 2, 3])
    }

    /// El error clásico de comparar versiones como texto: "1.10" < "1.9" alfabéticamente, y la
    /// actualización nunca se ofrece a partir de la décima.
    @Test("1.10 es mayor que 1.9, no menor")
    func decimaVersion() throws {
        #expect(try #require(Ver("1.9")) < #require(Ver("1.10")))
        #expect(try #require(Ver("0.9.0")) < #require(Ver("0.10.0")))
    }

    @Test("Rellenar con ceros: 1.2 y 1.2.0 son la misma")
    func rellenoConCeros() throws {
        #expect(try !(#require(Ver("1.2")) < #require(Ver("1.2.0"))))
        #expect(try !(#require(Ver("1.2.0")) < #require(Ver("1.2"))))
    }

    @Test("Un sufijo de prelanzamiento no rompe la lectura")
    func prelanzamiento() throws {
        #expect(try #require(Ver("v2.0.0-beta.3")).partes == [2, 0, 0])
    }

    @Test("Lo que no trae ningún número no es una versión")
    func basura() {
        #expect(Ver("") == nil)
        #expect(Ver("v") == nil)
        #expect(Ver("latest") == nil)
    }

    @Test("Ordena una lista como uno esperaría")
    func orden() throws {
        let versiones = try ["1.0.0", "0.9.9", "1.10.0", "1.2.0", "2.0.0"].map { try #require(Ver($0)) }
        #expect(versiones.sorted().map(\.description) == ["0.9.9", "1.0.0", "1.2.0", "1.10.0", "2.0.0"])
    }
}

/// La búsqueda de actualizaciones habla con la API de GitHub. Estos tests la ejercitan contra
/// un servidor de mentira, incluido el caso que ocurre HOY en este repositorio: sin releases
/// publicados, `releases/latest` devuelve 404 (comprobado contra api.github.com).
@Suite("Búsqueda de actualizaciones")
struct BusquedaDeActualizacionesTests {
    private func buscador(_ sesion: URLSession) -> BuscadorDeActualizaciones {
        BuscadorDeActualizaciones(repositorio: "quien/sea", sesion: sesion)
    }

    @Test("Sin releases publicados (404) no inventa una novedad")
    func sinReleases() async {
        let sesion = Servidor.sesion()
        Servidor.encolar(sesion, "/releases/latest", #"{"message":"Not Found"}"#, estado: 404)
        #expect(await buscador(sesion).buscar(versionActual: "1.0.0") == nil)
    }

    @Test("Una versión mayor sí es novedad")
    func hayNovedad() async throws {
        let sesion = Servidor.sesion()
        Servidor.encolar(sesion, "/releases/latest", #"""
        {"tag_name":"v1.2.0","html_url":"https://github.com/quien/sea/releases/tag/v1.2.0"}
        """#)
        let novedad = try #require(await buscador(sesion).buscar(versionActual: "1.1.9"))
        #expect(novedad.version.description == "1.2.0")
    }

    @Test("La misma versión no es novedad")
    func alDia() async {
        let sesion = Servidor.sesion()
        Servidor.encolar(sesion, "/releases/latest", #"{"tag_name":"v1.2.0","html_url":"https://x/y"}"#)
        #expect(await buscador(sesion).buscar(versionActual: "1.2.0") == nil)
    }

    /// Publicar un borrador o un prelanzamiento no debería empujar a nadie a actualizar.
    @Test("Borradores y prelanzamientos no cuentan", arguments: ["draft", "prerelease"])
    func borradores(campo: String) async {
        let sesion = Servidor.sesion()
        let cuerpo = #"{"tag_name":"v9.0.0","html_url":"https://x/y","\#(campo)":true}"#
        Servidor.encolar(sesion, "/releases/latest", cuerpo)
        #expect(await buscador(sesion).buscar(versionActual: "1.0.0") == nil)
    }
}
