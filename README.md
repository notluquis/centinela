# Centinela

Los issues de Sentry en la barra de menús de macOS: un número, una chispa de las últimas horas y el estado de los monitores de uptime, sin abrir el navegador.

No existe aplicación oficial de Sentry para macOS. La extensión de Sentry para Raycast tampoco sirve: sus dos comandos son `mode: "view"` — se puede leer en su manifiesto —, o sea buscador, no barra de menús. Esto llena ese hueco.

**Nativa de verdad**: SwiftUI, `MenuBarExtra`, 668 KB de aplicación. No es un contenedor web ni un script dentro de otra aplicación.

## Qué muestra

| Dónde | Qué | Cuándo se pide |
|---|---|---|
| En la barra | Errores de la ventana elegida, con chispa | Cada ciclo (5 min por omisión) |
| En la barra | Ícono rojo si un monitor de uptime está caído | Cada ciclo |
| En el panel | Issues sin resolver: proyecto, eventos, personas afectadas | Al abrir el panel |
| En el panel | Issues nuevos por revisar (`is:for_review`) | Al abrir el panel |
| En el panel | Últimos releases y cuántos issues nuevos trajo cada uno | Al abrir el panel |

Ese reparto es de dónde sale que sea liviano, y está medido contra una organización real:

| Ruta de la API | Tiempo | Tamaño |
|---|---|---|
| `events-stats` (el número y la chispa) | 378 ms | 937 B |
| `uptime` | 490 ms | 591 B |
| `issues` (la lista) | 1047 ms | 10,6 KB |

La lista de issues es **la ruta más cara de toda la API**: 3 veces más lenta y 11 veces más pesada que la serie. Por eso el ciclo periódico no la toca y sólo se pide al abrir el panel.

Reproducir la medición con tu propio token:

```bash
curl -s -o /dev/null -w '%{time_total}s %{size_download}B\n' \
  -H "Authorization: Bearer $TOKEN" \
  'https://sentry.io/api/0/organizations/TU_ORG/events-stats/?statsPeriod=24h&interval=1h&yAxis=count()&query=event.type:error&project=-1'
```

Dato que conviene saber antes de intentar optimizar: **la API de Sentry no expone `ETag` en ninguna de estas rutas**, así que no hay revalidación condicional (304) que aprovechar. Lo liviano se consigue pidiendo poco, no pidiendo barato. `gzip` sí está, y `URLSession` lo negocia sola.

Los límites medidos, por si vas a subir la frecuencia: 40 peticiones por ventana y por ruta (20 en `stats_v2`), 25 concurrentes, y la ventana se reinicia en menos de un segundo. El techo real no es Sentry sino la batería.

## Instalar

```bash
git clone https://github.com/notluquis/centinela.git
cd centinela
make instalar          # construye, arma el .app y lo copia a /Applications
open /Applications/Centinela.app
```

Luego: clic en el ícono → **Abrir ajustes** → organización y token.

Requiere macOS 14 o superior. **No requiere Xcode** — ver [Construir](#construir).

## El token

Centinela **sólo lee**. El token que le des debería reflejarlo.

1. En Sentry: *Settings → Developer Settings → Organization Tokens → Create New Token*.
2. Dale exactamente estos permisos y ninguno más:

| Permiso | Para qué |
|---|---|
| `org:read` | La organización, los monitores de uptime y los releases |
| `project:read` | La lista de proyectos |
| `event:read` | Los issues y la serie de errores |

3. Pégalo en Ajustes. Se guarda en el llavero de macOS con `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`: no se sincroniza a iCloud ni sale en un respaldo restaurado en otro equipo.

**No reutilices el token de `sentry-cli`.** Ese sube sourcemaps y publica releases, o sea trae permisos de escritura. Centinela lo detecta y lo dice en el panel: si el token puede leer `/audit-logs/` de la organización, no es de sólo lectura. El aviso existe porque el primer token que se usó acá fue justamente ése, y leía la auditoría sin chistar.

## Construir

```bash
make build     # swift build -c release
make test      # 15 tests de CentinelaCore, sin sesión gráfica
make app       # arma build/Centinela.app y lo firma ad-hoc
make run       # lo anterior, y lo abre
```

Compilación limpia en release: **60 s** en un Apple Silicon. La aplicación queda en 668 KB.

### Sin Xcode, con swiftly

Xcode no hace falta. [`swiftly`](https://www.swift.org/install/macos/swiftly/), el gestor oficial de toolchains de Swift, alcanza:

```bash
brew install swiftly
swiftly init
swiftly install 6.3.3 --use
```

Son unos 60 s de descarga contra los ~18 GB de Xcode, y desde ahí `swift build` compila SwiftUI, AppKit y ServiceManagement sin problema.

**Las Command Line Tools solas NO sirven**, y el error no ayuda:

```
error: failed to build module 'SwiftUI'; this SDK is not supported by the compiler
(the SDK is built with 'swiftlang-6.2.3.3.2', while this compiler is 'swiftlang-6.2.3.3.21')
```

El compilador de las CLT y su propio SDK vienen de compilaciones distintas. `softwareupdate --list` no ofrece arreglo, y apuntar a un SDK más viejo (`MacOSX15.4.sdk`) sólo cambia el error por `redefinition of module 'SwiftBridging'`. La toolchain de swiftly lo resuelve porque trae su propio compilador consistente.

Dato al margen: **Objective-C sí compila** con las CLT solas (`clang -framework Cocoa`, 1,2 s, binario de 52 KB). El bloqueo es específico de los módulos de Swift.

### Dos trampas que costaron tiempo acá

**`XCTest` no existe fuera de Xcode.** Viene con Xcode, no con la toolchain. La suite usa **Swift Testing**, que sí viene incluida — y que además es el marco por omisión desde 2026. Si migras tests viejos, no es opcional: con XCTest la suite deja de correr en una máquina sin Xcode.

**Swift Testing exporta su propio `Issue`.** Por eso el modelo de acá se llama `Incidencia` y no `Issue`: en un archivo con `import Testing`, el nombre corto se resuelve al de ellos. El síntoma no dice nada útil —el compilador emite `failed to produce diagnostic for expression` sobre la llamada a `decode`— y se pierde un buen rato revisando el `Codable`.

### Por qué no hay `.xcodeproj`

Un `project.pbxproj` es un archivo generado de decenas de miles de líneas que nadie revisa en un diff y que entra en conflicto con sólo abrirlo. Para una aplicación de un binario y sin extensiones, `swift build` más doce líneas de `Makefile` hacen lo mismo y se leen enteras.

El paquete está partido en dos objetivos por una razón concreta: `CentinelaCore` no importa AppKit ni SwiftUI, así que su suite corre sin sesión gráfica, en CI o en una terminal por SSH. Ahí vive todo lo que puede estar mal de una forma que no se ve —el parseo de las respuestas, la aritmética de la chispa, el llavero—; `Centinela` es sólo la carcasa que dibuja.

## Qué es "nativo" acá, concretamente

| | Centinela | SwiftBar + un script |
|---|---|---|
| En disco | **0,67 MB** | 7,1 MB |
| Residente | 8,8 MB | 7,8 MB |
| Por ciclo | nada: `async` dentro del proceso | **+19 MB y 1,5 s**, un intérprete que arranca de cero |
| Depende de | nada | de que SwiftBar siga instalado y siga funcionando |

Los dos números de memoria residente son parecidos y no se van a vender como si no lo fueran. La diferencia real está en la última fila: cada cinco minutos, para siempre.

- `MenuBarExtra` con `.menuBarExtraStyle(.window)` — un `NSMenu` no puede dibujar una chispa ni filas de dos líneas.
- `@Observable` (Observation), no `ObservableObject`.
- Llavero para el token, no un archivo de puntos.
- `SMAppService` para arrancar con la sesión — la forma vieja (`SMLoginItemSetEnabled` más un ejecutable auxiliar) quedó obsoleta en macOS 13. El estado no es un booleano: `.requiresApproval` significa registrado pero pendiente de que el usuario lo apruebe, y la interfaz lo dice en vez de mostrar el interruptor abajo.
- Liquid Glass (macOS 26+) sólo en los botones del pie, detrás de `#available`. El fondo del panel **no** se toca: `MenuBarExtra(.window)` ya lo dibuja con el material del sistema y apilar otro encima se ve turbio, no vidrioso.
- `URLSession` efímera: sin caché en disco, sin cookies, sin nada escrito.

## La barra de menús en macOS 26 y 27

- **macOS 26 (Tahoe)** dejó la barra transparente por omisión: los íconos quedan sobre el fondo de escritorio, no sobre una barra sólida. Por eso Centinela no fija colores en el ícono y deja que el sistema resuelva el contraste. El único color propio es el rojo de una caída, que es el estado que sí justifica romper la regla.
- **macOS 27 (Golden Gate)** rehízo el render de la barra y agregó un botón nativo para desplegar los íconos que no caben. En el camino rompió a Bartender, Ice, Thaw, Hidden Bar, Barbee, Sane Bar y Glow, que *administran* íconos ajenos. Agregar el propio es otra operación y no se vio afectada — verificado sobre macOS 27.0 beta (build 26A5416b).

## Distribución

Las compilaciones de CI van firmadas **ad-hoc**, sin Developer ID y sin notarizar. macOS pide confirmación la primera vez: clic derecho → Abrir.

Notarizar cuesta 99 USD al año y, para una herramienta que corre en los Macs de quien la construye, no se justifica. Si eso cambia: hace falta un `Developer ID Application` en el llavero del runner y un paso de `xcrun notarytool submit --wait`. El `Makefile` ya acepta `IDENTITY=` para no tener que tocarlo.

Verificar lo que bajaste:

```bash
codesign -dv --verbose=4 Centinela.app
spctl -a -t exec -vvv Centinela.app
```

## Lo que NO hace, a propósito

| No hace | Por qué |
|---|---|
| Notificaciones de escritorio | Sentry ya notifica por correo y por Slack. Duplicarlo son dos alarmas para el mismo evento. |
| Resolver, asignar o silenciar issues | El token es de sólo lectura y esa es la propiedad que se quiere conservar. Abre el issue en el navegador, donde sí hay sesión con permisos. |
| Guardar los issues en disco | Los títulos de error traen datos del negocio. La sesión de red es efímera. |
| Varias organizaciones | Una sola, la del token. Se agrega cuando haga falta de verdad. |
| Sentry autohospedado | Debería andar cambiando el servidor en Ajustes, pero no está probado. |

## Licencia

MIT. Ver [LICENSE](LICENSE).

Sin relación con Sentry (Functional Software, Inc.). Usa su API pública de lectura.
