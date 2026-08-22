import Foundation

/// Aviso de versión nueva leyendo la API de releases de GitHub.
///
/// **Por qué no Sparkle**, que es lo que usan Stats y TheBoringNotch: su propia documentación
/// de caja de arena dice que las distribuciones ad-hoc "no son ideales para distribución" y
/// que hay que re-firmar con un certificado de verdad. Sparkle además pide incrustar
/// `Installer.xpc`, activar `SUEnableInstallerLauncherService` y agregar dos excepciones
/// temporales de `mach-lookup` a los entitlements. Todo eso para instalar solo un binario que
/// igual va a chocar con Gatekeeper por estar firmado ad-hoc.
///
/// Esto avisa y abre la página. La persona baja y reemplaza. Sin XPC, sin excepciones de caja
/// de arena, sin certificado de 99 dólares al año.
public struct BuscadorDeActualizaciones: Sendable {
    public struct Version: Sendable, Equatable, Comparable, CustomStringConvertible {
        public let partes: [Int]

        /// Acepta `v1.2.3`, `1.2.3`, `1.2` y `1`. Lo que no sea número se descarta, así que
        /// `1.2.3-beta.1` se lee como `1.2.3`: para decidir "hay algo más nuevo" alcanza, y
        /// ordenar precedencia de prelanzamientos es un problema que este proyecto no tiene.
        public init?(_ texto: String) {
            let limpio = texto.trimmingCharacters(in: .whitespaces)
                .drop { $0 == "v" || $0 == "V" }
            let numeros = limpio
                .prefix { $0.isNumber || $0 == "." }
                .split(separator: ".")
                .compactMap { Int($0) }
            guard !numeros.isEmpty else { return nil }
            partes = numeros
        }

        public static func < (a: Version, b: Version) -> Bool {
            // Se comparan rellenando con ceros: `1.2` y `1.2.0` son la misma versión, y `1.10`
            // es mayor que `1.9`. Comparar los textos daría lo contrario.
            let largo = max(a.partes.count, b.partes.count)
            for i in 0..<largo {
                let x = i < a.partes.count ? a.partes[i] : 0
                let y = i < b.partes.count ? b.partes[i] : 0
                if x != y { return x < y }
            }
            return false
        }

        public var description: String { partes.map(String.init).joined(separator: ".") }
    }

    public struct Novedad: Sendable, Equatable {
        public let version: Version
        public let pagina: URL
    }

    private let repositorio: String
    private let sesion: URLSession

    public init(repositorio: String, sesion: URLSession = .shared) {
        self.repositorio = repositorio
        self.sesion = sesion
    }

    /// Devuelve la novedad si la hay, o `nil` si ya estás al día.
    ///
    /// Un fallo de red devuelve `nil` en vez de lanzar: no encontrar una actualización no es un
    /// error que le importe a nadie, y convertirlo en un aviso rojo en el panel entrena a la
    /// gente a ignorar los avisos rojos.
    public func buscar(versionActual: String) async -> Novedad? {
        guard let actual = Version(versionActual) else { return nil }

        var peticion = URLRequest(url: URL(string: "https://api.github.com/repos/\(repositorio)/releases/latest")!)
        peticion.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        peticion.setValue("centinela", forHTTPHeaderField: "User-Agent")

        guard
            let (datos, respuesta) = try? await sesion.data(for: peticion),
            let http = respuesta as? HTTPURLResponse, http.statusCode == 200,
            let json = try? JSONSerialization.jsonObject(with: datos) as? [String: Any],
            // `draft` y `prerelease` no cuentan: publicar un borrador no debería empujar a nadie
            // a actualizar.
            (json["draft"] as? Bool) != true,
            (json["prerelease"] as? Bool) != true,
            let etiqueta = json["tag_name"] as? String,
            let ultima = Version(etiqueta),
            let pagina = (json["html_url"] as? String).flatMap(URL.init(string:))
        else { return nil }

        return ultima > actual ? Novedad(version: ultima, pagina: pagina) : nil
    }
}
