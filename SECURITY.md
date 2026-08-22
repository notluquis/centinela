# Seguridad

## Qué maneja esta aplicación

Un token de la API de Sentry con permisos de lectura, y los títulos de los issues que ese token devuelve. Los títulos de error suelen traer URLs internas, identificadores y fragmentos de datos del negocio.

## Cómo se guarda

| Dato | Dónde | Detalle |
|---|---|---|
| Token | Llavero de macOS | `kSecClassGenericPassword`, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, sin sincronizar |
| Organización, servidor, intervalo | `UserDefaults` | No son secretos |
| Issues, releases, uptime | Sólo en memoria | `URLSessionConfiguration.ephemeral`: sin caché en disco, sin cookies |

Nada de lo que devuelve Sentry se escribe en disco.

## Permisos que pide la aplicación

Caja de arena activada. Dos permisos, y se pueden leer enteros en `Centinela.entitlements`:

- `com.apple.security.app-sandbox`
- `com.apple.security.network.client` — salir a la red

No pide archivos, ni cámara, ni contactos, ni servidor de red entrante. Si algún día aparece uno más, se ve en el diff.

## El token que le des

Dale `org:read`, `project:read` y `event:read`. Nada más. La aplicación no escribe en Sentry y no tiene código para hacerlo.

Centinela revisa si el token puede leer `/audit-logs/` de la organización. Si puede, trae permisos de escritura y lo dice en el panel. **No reutilices el token de `sentry-cli`**: ese sube sourcemaps y publica releases.

## Reportar un problema

Abre un issue en el repositorio. Si el hallazgo expone datos, escribe a la dirección del perfil de GitHub del autor en vez de abrirlo público.

## Lo que este proyecto no promete

- Las compilaciones publicadas van firmadas ad-hoc, sin notarizar. Verifica con `codesign -dv --verbose=4` y `spctl -a -t exec -vvv` antes de abrir lo que bajaste.
- No hay actualizaciones automáticas. Nada se descarga ni se ejecuta solo.
