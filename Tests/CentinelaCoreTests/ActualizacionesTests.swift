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
