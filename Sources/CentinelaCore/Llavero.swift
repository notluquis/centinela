import Foundation
import Security

/// El token vive en el llavero, no en `UserDefaults` ni en un archivo de puntos.
///
/// El motivo no es teórico: el token que arrancó este proyecto estaba en `~/.sentryclirc` en
/// texto plano, legible por cualquier proceso corriendo como el usuario, y respaldado a donde
/// sea que se respalde la carpeta personal. Un token de organización de Sentry no caduca solo.
public enum Llavero {
    public static let servicio = "cl.bioalergia.centinela"

    public enum Falla: Error, LocalizedError {
        case sistema(OSStatus)

        public var errorDescription: String? {
            switch self {
            case .sistema(let estado):
                let texto = SecCopyErrorMessageString(estado, nil) as String? ?? "código \(estado)"
                return "El llavero respondió: \(texto)"
            }
        }
    }

    public static func leer(cuenta: String) throws -> String? {
        var consulta = base(cuenta: cuenta)
        consulta[kSecReturnData as String] = true
        consulta[kSecMatchLimit as String] = kSecMatchLimitOne

        var resultado: CFTypeRef?
        let estado = SecItemCopyMatching(consulta as CFDictionary, &resultado)
        switch estado {
        case errSecSuccess:
            guard let datos = resultado as? Data else { return nil }
            return String(data: datos, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw Falla.sistema(estado)
        }
    }

    public static func guardar(_ valor: String, cuenta: String) throws {
        let datos = Data(valor.utf8)
        let consulta = base(cuenta: cuenta)

        // Se intenta actualizar antes de agregar. `SecItemAdd` sobre un ítem existente
        // devuelve `errSecDuplicateItem` en vez de reemplazarlo, así que el orden importa.
        let cambio = [kSecValueData as String: datos] as CFDictionary
        let actualizado = SecItemUpdate(consulta as CFDictionary, cambio)
        if actualizado == errSecSuccess { return }
        if actualizado != errSecItemNotFound { throw Falla.sistema(actualizado) }

        var nuevo = consulta
        nuevo[kSecValueData as String] = datos
        // Sólo cuando el equipo está desbloqueado, y sin sincronizar a iCloud ni salir en
        // respaldos a otro dispositivo.
        nuevo[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let agregado = SecItemAdd(nuevo as CFDictionary, nil)
        guard agregado == errSecSuccess else { throw Falla.sistema(agregado) }
    }

    public static func borrar(cuenta: String) throws {
        let estado = SecItemDelete(base(cuenta: cuenta) as CFDictionary)
        guard estado == errSecSuccess || estado == errSecItemNotFound else {
            throw Falla.sistema(estado)
        }
    }

    private static func base(cuenta: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: servicio,
            kSecAttrAccount as String: cuenta,
            kSecAttrSynchronizable as String: false
        ]
    }
}
