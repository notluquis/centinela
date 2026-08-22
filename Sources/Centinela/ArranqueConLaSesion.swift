import Observation
import ServiceManagement

/// Arrancar al iniciar sesión, con `SMAppService` (macOS 13+).
///
/// La forma vieja —un ejecutable auxiliar en `Contents/Library/LoginItems` registrado con
/// `SMLoginItemSetEnabled`— quedó obsoleta en macOS 13 y obliga a empaquetar un segundo binario.
/// `SMAppService.mainApp` registra la aplicación misma: sin auxiliar, sin código extra, y el
/// usuario la ve y la puede apagar en Ajustes del Sistema → General → Ítems de inicio.
///
/// El estado NO es un booleano: `.requiresApproval` significa que el registro quedó hecho pero
/// el usuario todavía no lo aprobó en Ajustes del Sistema. Tratarlo como "apagado" haría que la
/// interfaz mostrara el interruptor abajo mientras el sistema lo tiene arriba esperando.
@MainActor
@Observable
final class ArranqueConLaSesion {
    private(set) var estado: SMAppService.Status = .notRegistered
    private(set) var ultimoError: String?

    init() { refrescar() }

    var activo: Bool { estado == .enabled }

    var necesitaAprobacion: Bool { estado == .requiresApproval }

    func refrescar() { estado = SMAppService.mainApp.status }

    func alternar(_ encendido: Bool) {
        do {
            if encendido {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            ultimoError = nil
        } catch {
            ultimoError = error.localizedDescription
        }
        refrescar()
    }

    /// Abre el panel donde el usuario aprueba o revoca el ítem de inicio. Es el único camino:
    /// una aplicación no puede aprobarse a sí misma.
    func abrirAjustesDelSistema() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
