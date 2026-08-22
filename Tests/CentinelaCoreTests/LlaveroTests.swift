import Foundation
import Testing

@testable import CentinelaCore

/// El llavero es la afirmación central de seguridad del proyecto y hasta acá no tenía un solo
/// test. Estos hacen el viaje de ida y vuelta contra el llavero real, con una cuenta propia que
/// se borra al terminar.
///
/// Corren en serie: comparten una cuenta en un almacén global del sistema, y en paralelo se
/// pisarían entre ellos.
@Suite("Llavero", .serialized)
struct LlaveroTests {
    private let cuenta = "prueba-automatizada-centinela"

    private func limpiar() { try? Llavero.borrar(cuenta: cuenta) }

    @Test("Guardar y volver a leer devuelve exactamente lo mismo")
    func idaYVuelta() throws {
        limpiar()
        defer { limpiar() }

        // Con caracteres que no son ASCII: el valor viaja como `Data` en UTF-8 y una conversión
        // descuidada los perdería en silencio.
        let secreto = "sntrys_ñÑáé·\(UUID().uuidString)"
        try Llavero.guardar(secreto, cuenta: cuenta)
        #expect(try Llavero.leer(cuenta: cuenta) == secreto)
    }

    /// `SecItemAdd` sobre un ítem que ya existe devuelve `errSecDuplicateItem` en vez de
    /// reemplazarlo. Por eso `guardar` intenta actualizar primero; sin ese orden, cambiar el
    /// token fallaría siempre a partir del segundo.
    @Test("Guardar dos veces reemplaza, no duplica ni falla")
    func sobrescribir() throws {
        limpiar()
        defer { limpiar() }

        try Llavero.guardar("primero", cuenta: cuenta)
        try Llavero.guardar("segundo", cuenta: cuenta)
        #expect(try Llavero.leer(cuenta: cuenta) == "segundo")
    }

    @Test("Una cuenta que no existe devuelve nil, no un error")
    func ausente() throws {
        limpiar()
        #expect(try Llavero.leer(cuenta: "cuenta-que-no-existe-\(UUID().uuidString)") == nil)
    }

    @Test("Borrar dos veces no falla la segunda")
    func borrarEsIdempotente() throws {
        try Llavero.guardar("x", cuenta: cuenta)
        try Llavero.borrar(cuenta: cuenta)
        try Llavero.borrar(cuenta: cuenta)
        #expect(try Llavero.leer(cuenta: cuenta) == nil)
    }
}
