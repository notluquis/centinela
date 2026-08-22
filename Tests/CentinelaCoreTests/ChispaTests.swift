import Testing

@testable import CentinelaCore

@Suite("Aritmética de la chispa")
struct ChispaTests {
    @Test("Una serie vacía no devuelve puntos")
    func vacia() {
        #expect(Chispa.normalizar([]).isEmpty)
    }

    @Test("Un solo punto se ancla al centro")
    func unPunto() {
        let puntos = Chispa.normalizar([7])
        #expect(puntos.count == 1)
        #expect(puntos[0].x == 0.5)
        #expect(puntos[0].y == 0.5)
    }

    /// El caso que importa: sin errores la serie es todo ceros y `maximo - minimo` da 0.
    /// Dividir ahí produce `NaN`, que Core Graphics NO reporta como error: dibuja nada, y el
    /// widget se ve "sin datos" justo cuando el sistema está sano.
    @Test("Una serie plana da línea al medio y nunca NaN", arguments: [[0, 0, 0, 0], [5, 5, 5]])
    func plana(valores: [Int]) {
        let puntos = Chispa.normalizar(valores)
        #expect(puntos.count == valores.count)
        for punto in puntos {
            #expect(!punto.y.isNaN)
            #expect(punto.y == 0.5)
        }
    }

    @Test("Una serie normal deja el mínimo abajo y el máximo arriba")
    func normal() {
        let puntos = Chispa.normalizar([0, 5, 10])
        #expect(puntos.map(\.y) == [0, 0.5, 1])
        #expect(puntos.map(\.x) == [0, 0.5, 1])
    }

    @Test("Todo queda dentro del cuadrado unitario")
    func dentroDelCuadrado() {
        let puntos = Chispa.normalizar([3, 100, 0, 42, 7])
        #expect(puntos.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
    }

    @Test("El resumen distingue cero de algo")
    func resumen() {
        #expect(Chispa.resumen([0, 0], ventana: .veinticuatroHoras) == "Sin errores en 24 horas.")
        let conErrores = Chispa.resumen([1, 4], ventana: .veinticuatroHoras)
        #expect(conErrores == "5 errores en 24 horas, pico de 4 por intervalo.")
    }
}
