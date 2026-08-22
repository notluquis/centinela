import AppKit
import CentinelaCore
import Observation
import SwiftUI

/// Todo el estado que la interfaz observa, y el único sitio que decide CUÁNDO se llama a la API.
///
/// El reparto no es cosmético. `refrescarLoBarato()` corre en cada ciclo del temporizador y pide
/// las dos rutas medidas como baratas (serie de errores 378 ms / 937 B, uptime 490 ms).
/// `refrescarLoCaro()` pide la lista de incidencias (1047 ms / 10,6 KB) y sólo se llama al abrir el
/// panel. La API de Sentry no expone ETag en ninguna ruta, así que no hay revalidación
/// condicional que aprovechar: lo liviano se consigue pidiendo poco, no pidiendo barato.
@MainActor
@Observable
final class Estado {
    var serie: SerieDeEventos = .init(puntos: [])
    var monitores: [MonitorDeUptime] = []
    var incidencias: [Incidencia] = []
    var porRevisar: [Incidencia] = []
    var releases: [Release] = []

    var novedad: BuscadorDeActualizaciones.Novedad?
    var cargando = false
    var ultimoError: String?
    var ultimaActualizacion: Date?
    var tokenConDemasiadoPoder = false

    @ObservationIgnored private var temporizador: Timer?
    @ObservationIgnored private var observadores: [NSObjectProtocol] = []
    @ObservationIgnored private var dormido = false

    var ajustes: Ajustes
    let sesion: InicioDeSesion

    // El parámetro es opcional y no `= Ajustes()`: los valores por omisión se evalúan en un
    // contexto sin aislamiento, y `Ajustes` está en el actor principal. Con el default directo
    // el compilador rechaza la llamada (`#ActorIsolatedCall`).
    init(ajustes: Ajustes? = nil) {
        let a = ajustes ?? Ajustes()
        self.ajustes = a
        self.sesion = InicioDeSesion(ajustes: a)
        observarSuspension()
    }

    deinit {
        // `deinit` no corre en el actor principal; se saca el observador sin tocar `self`.
        let centro = NSWorkspace.shared.notificationCenter
        for o in observadores { centro.removeObserver(o) }
    }

    private var cliente: ClienteDeSentry? {
        guard let credenciales = ajustes.credenciales() else { return nil }
        return ClienteDeSentry(credenciales: credenciales)
    }

    // MARK: - Ciclo

    static let repositorio = "notluquis/centinela"

    var versionInstalada: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    func arrancar() {
        reprogramar()
        Task { await refrescarLoBarato() }
        Task { await buscarActualizacion() }
    }

    /// Una vez al día, no en cada arranque. La API de GitHub limita a 60 peticiones por hora
    /// sin autenticar, y una aplicación de barra de menús puede reiniciarse muchas veces al día
    /// mientras alguien la configura.
    func buscarActualizacion(forzar: Bool = false) async {
        let clave = "ultimaBusquedaDeActualizacion"
        let ultima = UserDefaults.standard.double(forKey: clave)
        let hace = Date().timeIntervalSince1970 - ultima
        guard forzar || hace > 86_400 else { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: clave)

        let buscador = BuscadorDeActualizaciones(repositorio: Self.repositorio)
        novedad = await buscador.buscar(versionActual: versionInstalada)
    }

    func reprogramar() {
        temporizador?.invalidate()
        let cada = ajustes.intervaloSegundos
        let t = Timer(timeInterval: cada, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refrescarLoBarato() }
        }
        // Tolerancia generosa: le deja al sistema juntar este despertar con otros en vez de
        // sacar el procesador de reposo sólo para nosotros. En una aplicación que consulta
        // cada varios minutos, la precisión al segundo no compra nada y sí cuesta batería.
        t.tolerance = cada * 0.2
        RunLoop.main.add(t, forMode: .common)
        temporizador = t
    }

    /// Al suspender el equipo se detiene el temporizador y al despertar se refresca de
    /// inmediato. Sin esto, `Timer` acumula el disparo perdido y dispara al despertar de todas
    /// formas, pero con datos de antes de dormir en pantalla hasta el ciclo siguiente.
    private func observarSuspension() {
        let centro = NSWorkspace.shared.notificationCenter
        observadores.append(centro.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.dormido = true
                self?.temporizador?.invalidate()
            }
        })
        observadores.append(centro.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.dormido = false
                self?.reprogramar()
                await self?.refrescarLoBarato()
            }
        })
    }

    // MARK: - Peticiones

    func refrescarLoBarato() async {
        guard !dormido else { return }
        // Antes de pedir nada: si el token OAuth está por vencer, se renueva. Va acá y no en un
        // temporizador aparte porque lo que importa es tener un token vivo justo cuando se va a
        // usar, no haber intentado renovar mientras la máquina dormía.
        if let falloDeRenovacion = await sesion.refrescarSiHaceFalta() {
            ultimoError = falloDeRenovacion
        }
        guard let cliente else { return }
        cargando = true
        defer { cargando = false }
        do {
            async let serie = cliente.serieDeErrores(ventana: ajustes.ventana)
            async let monitores = cliente.monitoresDeUptime()
            self.serie = try await serie
            self.monitores = try await monitores
            ultimoError = nil
            ultimaActualizacion = .now
        } catch {
            ultimoError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func refrescarLoCaro() async {
        guard let cliente else { return }
        cargando = true
        defer { cargando = false }
        do {
            async let incidencias = cliente.issuesSinResolver(ventana: ajustes.ventana, limite: ajustes.maximoIssues)
            async let porRevisar = cliente.issuesPorRevisar()
            async let releases = cliente.ultimosReleases()
            self.incidencias = try await incidencias
            self.porRevisar = try await porRevisar
            self.releases = try await releases
            ultimoError = nil
        } catch {
            ultimoError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func revisarPoderDelToken() async {
        guard let cliente else { return }
        tokenConDemasiadoPoder = await !cliente.tokenPareceDeSoloLectura()
    }

    // MARK: - Lo que se dibuja arriba

    var totalDeErrores: Int { serie.total }

    var hayCaida: Bool { monitores.contains { $0.activo && !$0.sano } }

    var estadoGeneral: Severidad {
        if hayCaida { return .fatal }
        return totalDeErrores > 0 ? .error : .info
    }
}
