# Centinela

Los issues de Sentry en la barra de menús de macOS: un número, una chispa de las últimas horas y el estado de los monitores de uptime, sin abrir el navegador.

No existe aplicación oficial de Sentry para macOS, y tampoco una de terceros. Buscado el 2026-08-22:

| Dónde se buscó | Resultado |
|---|---|
| Repositorios de GitHub (4 consultas) | Nada. Todo lo que sale usa "sentry" como sustantivo común: puertos, notch, pomodoro |
| Extensión de Sentry para Raycast | Sus dos comandos son `mode: "view"`, o sea buscador. Sin comando de barra de menús |
| Casks de Homebrew | Sólo `sentry-cli` |
| Plugins de xbar | Uno, apuntando al dominio legacy `app.getsentry.com` y a un solo proyecto |

Esto llena ese hueco.

**Nativa de verdad**: SwiftUI, `MenuBarExtra`, 2 MB de aplicación. No es un contenedor web ni un script dentro de otra aplicación.

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

Requiere macOS 14 o superior. **No requiere Xcode**. Ver [Construir](#construir).

## Iniciar sesión

Centinela **sólo lee**, y hay dos formas de darle acceso.

### Con el flujo de dispositivo

> **Sin probar de punta a punta todavía**, porque hace falta un identificador de cliente real. Lo que sí está verificado: el endpoint existe y responde en sentry.io, y once tests ejercitan el cliente entero contra un servidor de mentira.

Clic en "Iniciar sesión con Sentry": la aplicación pide un código, abre el navegador, tú apruebas, y Sentry entrega un token con **exactamente** los permisos que se pidieron.

Los que pide Centinela, y ningunos más:

```
org:read  project:read  event:read
```

Hay un test que se pone rojo si alguien agrega uno de escritura, porque los permisos son parte del contrato con quien usa esto, no un detalle interno.

#### Qué hay que crear en Sentry

Una **API Application**, que NO está donde uno buscaría:

| | |
|---|---|
| Dónde | `https://sentry.io/settings/account/api/applications/` (Ajustes de **tu cuenta**, API, Applications) |
| Qué NO es | No es una integración interna ni pública de *Developer Settings*: esas entregan un token o son para el flujo de código de autorización. El flujo de dispositivo busca un `ApiApplication` |
| Qué entrega | `Client ID` y `Client Secret`. Acá sólo se usa el **Client ID** |
| Requisitos | Ninguno especial: no hay que marcar nada para el flujo de dispositivo, y no hace falta publicar la aplicación. Sólo tiene que estar activa |

Verificado leyendo `src/sentry/web/frontend/oauth_device_authorization.py` en el repositorio de Sentry: el endpoint hace `ApiApplication.objects.get(client_id=..., status=active)` y nada más. Los permisos se validan contra la lista global de Sentry, y contra los de la aplicación sólo si esta marcó `requires_org_level_access`.

El Client ID se pega en Ajustes, pestaña Cuenta. No es secreto (el RFC 8628 trata a estos clientes como públicos) y por eso vive en `UserDefaults` y no en el llavero. El token de acceso y el de refresco sí van al llavero.

El token se renueva solo cuando le queda menos del 10 % de vida, que es el criterio de `sentry-cli`. Si la renovación falla, la sesión **no** se cierra: puede ser que no haya red, y el token viejo sigue sirviendo hasta que Sentry responda 401.

### Con un token pegado a mano

Sigue funcionando, y es la única vía en instancias anteriores a Sentry 26.1.0 (ahí el endpoint no existe y la aplicación lo dice con esas palabras en vez de dar un error genérico).

1. En Sentry: *Settings, Developer Settings, Organization Tokens, Create New Token*.
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

Compilación limpia en release: **60 s** en un Apple Silicon. La aplicación queda en 2 MB, de los cuales 1,1 son el `.icns`.

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

**`XCTest` no existe fuera de Xcode.** Viene con Xcode, no con la toolchain. La suite usa **Swift Testing**, que sí viene incluida y que además es el marco por omisión desde 2026. Si migras tests viejos, no es opcional: con XCTest la suite deja de correr en una máquina sin Xcode.

**Swift Testing exporta su propio `Issue`.** Por eso el modelo de acá se llama `Incidencia` y no `Issue`: en un archivo con `import Testing`, el nombre corto se resuelve al de ellos. El síntoma no dice nada útil (el compilador emite `failed to produce diagnostic for expression` sobre la llamada a `decode`) y se pierde un buen rato revisando el `Codable`.

### Por qué no hay `.xcodeproj`

Un `project.pbxproj` es un archivo generado de decenas de miles de líneas que nadie revisa en un diff y que entra en conflicto con sólo abrirlo. Para una aplicación de un binario y sin extensiones, `swift build` más doce líneas de `Makefile` hacen lo mismo y se leen enteras.

El paquete está partido en dos objetivos por una razón concreta: `CentinelaCore` no importa AppKit ni SwiftUI, así que su suite corre sin sesión gráfica, en CI o en una terminal por SSH. Ahí vive todo lo que puede estar mal de una forma que no se ve (el parseo de las respuestas, la aritmética de la chispa, el llavero); `Centinela` es sólo la carcasa que dibuja.

## Qué es "nativo" acá, concretamente

| | Centinela | SwiftBar + un script |
|---|---|---|
| En disco | **2,0 MB** (1,1 son el ícono) | 7,1 MB |
| Residente, sin abrir el panel | 7,6 MB | 6–8 MB |
| Residente, después de abrirlo | ~25 MB | 6–8 MB |
| Por ciclo | nada: `async` dentro del proceso | **+19 MB y 1,5 s**, un intérprete que arranca de cero |
| Depende de | nada | de que SwiftBar siga instalado y siga funcionando |

**Abrir el panel triplica la memoria y no baja.** SwiftUI construye la ventana la primera vez que se despliega y se queda con ella. Antes de eso las dos aplicaciones gastan lo mismo. Si el criterio es la RAM en régimen, SwiftBar gana, y conviene saberlo antes de instalar nada.

Lo que sí gana Centinela: 10 veces menos en disco, ningún proceso que nazca y muera cada cinco minutos para siempre, y no depender de que una segunda aplicación siga instalada y siga funcionando, que en macOS 27, con la barra de menús rehecha, dejó de ser una suposición gratis.

- `MenuBarExtra` con `.menuBarExtraStyle(.window)`: un `NSMenu` no puede dibujar una chispa ni filas de dos líneas.
- `@Observable` (Observation), no `ObservableObject`.
- Llavero para el token, no un archivo de puntos.
- `SMAppService` para arrancar con la sesión. La forma vieja (`SMLoginItemSetEnabled` más un ejecutable auxiliar) quedó obsoleta en macOS 13. El estado no es un booleano: `.requiresApproval` significa registrado pero pendiente de que el usuario lo apruebe, y la interfaz lo dice en vez de mostrar el interruptor abajo.
- Liquid Glass según la guía oficial de Apple ([Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)), que dice tres cosas que acá se siguen al pie de la letra:
  1. *"Instead of creating buttons with custom Liquid Glass effects, adopt the look and feel of the material with minimal code by using one of the button style APIs"*. Por eso `.buttonStyle(.glass)` y no un fondo dibujado a mano.
  2. *"Audit the backgrounds of sheets and popovers […] remove those custom background views"*. Por eso el fondo del panel no se toca: `MenuBarExtra(.window)` ya lo dibuja el sistema, y apilar otro material encima se ve turbio, no vidrioso.
  3. *"Combine custom Liquid Glass effects […] using a GlassEffectContainer, which helps optimize performance while fluidly morphing Liquid Glass shapes into each other"*. Por eso los tres botones del pie van en un solo contenedor y no sueltos.
  Todo detrás de `#available(macOS 26.0)`: en 14 y 15 cae al estilo plano, que es el correcto ahí.
- `URLSession` efímera: sin caché en disco, sin cookies, sin nada escrito.

## La barra de menús en macOS 26 y 27

- **macOS 26 (Tahoe)** dejó la barra transparente por omisión: los íconos quedan sobre el fondo de escritorio, no sobre una barra sólida. Por eso Centinela no fija colores en el ícono y deja que el sistema resuelva el contraste. El único color propio es el rojo de una caída, que es el estado que sí justifica romper la regla.
- **macOS 27 (Golden Gate)** rehízo el render de la barra y agregó un botón nativo para desplegar los íconos que no caben. En el camino rompió a Bartender, Ice, Thaw, Hidden Bar, Barbee, Sane Bar y Glow, que *administran* íconos ajenos. Agregar el propio es otra operación y no se vio afectada. Verificado sobre macOS 27.0 beta (build 26A5416b).

## Actualizaciones

Centinela **avisa** de versiones nuevas leyendo la API de releases de GitHub una vez al día. No se actualiza sola.

Stats y TheBoringNotch usan [Sparkle](https://sparkle-project.org), que sí instala solo. Acá no sirve, y no es una preferencia:

| Lo que Sparkle pide | Estado acá |
|---|---|
| Un certificado de verdad para distribuir | No hay. Su propia documentación dice que las distribuciones ad-hoc "no son ideales para distribución" y hay que re-firmar |
| Incrustar `Installer.xpc` y activar `SUEnableInstallerLauncherService` | Se podría |
| Dos excepciones temporales de `mach-lookup` en los entitlements | Rompe la promesa de "dos permisos y se leen enteros" |

Y aunque todo eso se hiciera, el binario instalado seguiría siendo ad-hoc y chocaría con Gatekeeper igual. Avisar y abrir la página es la parte que de verdad sirve.

## Sin atajo de teclado global

Sería lo natural en una aplicación de barra de menús, y **no se puede**: `MenuBarExtra` no expone ninguna forma de abrir su ventana desde código. Es un pedido abierto en el sistema de feedback de Apple ([FB10185203](https://github.com/feedback-assistant/reports/issues/328)), sin resolver a agosto de 2026.

La salida sería abandonar `MenuBarExtra` y manejar un `NSStatusItem` con un `NSPanel` propio, que es un rediseño completo por un atajo. Queda anotado, no hecho.

## Distribución

Las compilaciones de CI van firmadas **ad-hoc**, sin Developer ID y sin notarizar. macOS pide confirmación la primera vez: clic derecho → Abrir.

Notarizar cuesta 99 USD al año y, para una herramienta que corre en los Macs de quien la construye, no se justifica. Si eso cambia: hace falta un `Developer ID Application` en el llavero del runner y un paso de `xcrun notarytool submit --wait`. El `Makefile` ya acepta `IDENTITY=` para no tener que tocarlo.

Verificar lo que bajaste:

```bash
codesign -dv --verbose=4 Centinela.app
spctl -a -t exec -vvv Centinela.app
```

## Por qué consulta en vez de esperar un aviso

Sentry sí tiene webhooks, y no sirven acá. Sus notificaciones son un POST a una URL, y para recibir uno hay que ser **alcanzable desde internet público**: un servidor, un túnel, algo que esté siempre encendido. Una aplicación de escritorio no es nada de eso, y montar un relay para no consultar cada cinco minutos es cambiar una consulta barata por una pieza de infraestructura que hay que mantener y pagar.

Tampoco hay API de streaming: ni SSE ni websocket para issues.

Lo que sí se hace para no consultar de más:

| Medida | Efecto |
|---|---|
| El panel pide al abrirse | Cuando miras, los datos son de ese segundo, no del último ciclo |
| El ciclo pide sólo las dos rutas baratas | 1,5 KB, no 10,6 KB |
| `Timer` con 20 % de tolerancia | Deja que el sistema junte el despertar con otros en vez de sacar el procesador de reposo sólo para esto |
| Se detiene al suspender el equipo y refresca al despertar | Cero peticiones mientras la tapa está cerrada |

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
