# Instrucciones para agentes de IA

Este proyecto es una aplicación de barra de menús que lee la API de Sentry con un token. Las reglas de abajo no son preferencias de estilo: cada una nombra algo que ya pasó.

## Reglas que no se negocian

**1. Sólo lectura, siempre.** Nada que escriba en Sentry: ni resolver, ni asignar, ni silenciar, ni publicar releases. No debe existir el código, ni siquiera desactivado ni detrás de una bandera. La propiedad que se protege es que el token pueda ser de sólo lectura; en cuanto haya una ruta de escritura, el usuario necesita un token con más poder y la garantía se vacía.

**2. El token va en el llavero.** Nunca en `UserDefaults`, nunca en un archivo, nunca en un log, nunca en un mensaje de error. Un token de organización de Sentry no caduca solo. El proyecto empezó porque el token estaba en `~/.sentryclirc` en texto plano.

**3. Nada de datos reales en el repositorio.** Las fixtures son inventadas y así se quedan: las respuestas de verdad traen títulos de error con URLs internas y datos del negocio, y esto es público. Hay un job de CI que falla si aparece algo con forma de token de Sentry o un nombre real en las fixtures. Los dos guardias se probaron inyectando la violación, no sólo mirándolos pasar.

**4. Nada se escribe en disco en ejecución.** `URLSessionConfiguration.ephemeral`, sin caché, sin cookies. Si algún día hace falta persistir algo, que no sean títulos de issues.

**5. Un número medido o nada.** El README afirma tiempos y tamaños de la API. Si vas a cambiar uno, córrelo; si vas a agregar uno, mídelo. Un número copiado de la documentación de Sentry no es un número medido.

## Lo que hay que entender antes de tocar el cliente

**El reparto barato/caro es la arquitectura, no una optimización.** `refrescarLoBarato()` corre en cada ciclo y pide `events-stats` (378 ms / 937 B) y `uptime` (490 ms). `refrescarLoCaro()` pide la lista de issues (1047 ms / 10,6 KB) y **sólo** se llama al abrir el panel. Mover la lista al ciclo periódico multiplica por once el tráfico de la aplicación para que nadie mire el resultado.

**No hay `ETag` en la API de Sentry.** Se midió: ninguna de estas rutas lo devuelve, así que no existe el 304. Si alguien propone "cachear con revalidación condicional", la respuesta es que no hay con qué.

**Las tres formas raras de la respuesta.** Están comentadas en el código, en el sitio exacto donde muerden, y cada una tiene su test:

| Campo | Lo que uno esperaría | Lo que manda Sentry |
|---|---|---|
| `issue.count` | número | **texto** (`"13"`), mientras que `userCount` sí es número |
| fechas | un formato | **dos**: con y sin fracción de segundo, en la misma respuesta |
| `events-stats.data` | objetos | pares heterogéneos `[epoch, [{"count": n}]]` |

Declarar `count` como `Int` no rompe ese campo: hace fallar el arreglo completo con `typeMismatch`.

## Trampas de la toolchain

**`XCTest` no existe fuera de Xcode.** La suite usa Swift Testing y así debe quedarse: con XCTest deja de correr en una máquina con sólo `swiftly`, que es el flujo que el README documenta.

**Swift Testing exporta su propio `Issue`.** Por eso el modelo se llama `Incidencia`. Si renombras a `Issue`, cualquier archivo con `import Testing` deja de compilar con `failed to produce diagnostic for expression`, que no menciona la ambigüedad por ningún lado.

**Un valor por omisión no se evalúa en el actor principal.** `init(ajustes: Ajustes = Ajustes())` sobre un tipo `@MainActor` da `#ActorIsolatedCall`. Va como `Ajustes? = nil` y se resuelve dentro.

## Idioma y estilo

- Español de Chile. Nada de voseo (`revisa`, no `revisá`).
- Los identificadores están en español, salvo los que vienen de la API o de Apple.
- Los comentarios explican **por qué**, no qué. Un comentario que parafrasea la línea siguiente se borra.
- Los mensajes de commit y los PR se escriben como registro público: sin segunda persona, sin agradecimientos, sin "como dijiste".

## Antes de dar algo por terminado

```bash
swift build -c release   # cero errores y cero avisos
swift test               # 15 tests, todos verdes
make app                 # el bundle se arma y la firma verifica
```

Y si agregaste un guardia, rómpelo una vez y confirma que se pone en rojo. Un guardia que no puede fallar imprime exactamente lo mismo que uno que protege.
