import Foundation

/// La chispa (sparkline) que va al lado del número, en la barra.
///
/// Acá vive sólo la aritmética —normalizar una serie a puntos entre 0 y 1— porque es lo único
/// que puede estar mal de una forma que no se ve a simple vista. El dibujo va en el objetivo
/// de la aplicación, donde no hay nada que testear.
public enum Chispa {
    /// Normaliza a coordenadas `0...1`, con `y = 0` abajo.
    ///
    /// Tres casos que un `map` ingenuo arruina:
    /// - serie vacía → sin puntos, no una división por cero;
    /// - un solo punto → no hay ancho sobre el cual repartir, se ancla al centro;
    /// - serie plana (todo el mismo valor, incluido todo en cero) → línea al medio, no arriba
    ///   ni abajo. `maximo - minimo` es 0 y dividir por ahí da `NaN`, que en Core Graphics no
    ///   levanta un error: dibuja nada, y el widget se ve "sin datos" cuando sí los hay.
    public static func normalizar(_ valores: [Int]) -> [(x: Double, y: Double)] {
        guard !valores.isEmpty else { return [] }
        guard valores.count > 1 else { return [(x: 0.5, y: 0.5)] }

        let maximo = valores.max() ?? 0
        let minimo = valores.min() ?? 0
        let rango = Double(maximo - minimo)
        let ultimoIndice = Double(valores.count - 1)

        return valores.enumerated().map { indice, valor in
            let x = Double(indice) / ultimoIndice
            let y = rango > 0 ? Double(valor - minimo) / rango : 0.5
            return (x: x, y: y)
        }
    }

    /// Resume la serie en una frase corta para la ayuda emergente y para VoiceOver.
    public static func resumen(_ valores: [Int], ventana: Ventana) -> String {
        let total = valores.reduce(0, +)
        guard total > 0 else { return "Sin errores en \(ventana.etiqueta)." }
        let pico = valores.max() ?? 0
        return "\(total) errores en \(ventana.etiqueta), pico de \(pico) por intervalo."
    }
}
