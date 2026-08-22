# Cambios

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/).
Versionado semántico.

## [0.1.0] — 2026-08-22

Primera versión publicada. Firma ad-hoc, sin notarizar: la primera vez macOS pide confirmación (clic derecho sobre la aplicación, Abrir).

### En la barra de menús

- Conteo de errores de la ventana elegida, con una chispa de la serie al lado.
- Ícono rojo cuando un monitor de uptime está caído.
- El ícono no fija colores: en macOS 26 y 27 la barra es transparente y encima va el papel tapiz, así que el contraste lo resuelve el sistema. El único color propio es el rojo de una caída.

### En el panel

- Issues sin resolver con proyecto, eventos y personas afectadas. Clic abre el issue en Sentry.
- Issues nuevos por revisar (`is:for_review`).
- Últimos releases y cuántos issues nuevos trajo cada uno.
- Estado de los monitores de uptime.
- Aviso si Sentry anuncia que va a retirar una de las rutas que la aplicación usa.

### Inicio de sesión

- Flujo de dispositivo de OAuth 2.0 (RFC 8628), lo mismo que usa `sentry-cli`. La aplicación declara `org:read`, `project:read` y `event:read`; Sentry entrega un token con exactamente esos y nada más.
- El identificador de cliente viene incluido: no hay nada que configurar. Quien prefiera registrar el suyo lo pega en Ajustes.
- Renovación automática bajo el 10 % de vida restante. Una renovación fallida no cierra la sesión: puede ser falta de red.
- Sigue funcionando pegar un token a mano, que es la única vía en instancias anteriores a Sentry 26.1.0.
- Avisa si el token puede leer la bitácora de auditoría de la organización, o sea si trae permisos de escritura que la aplicación no necesita.

### Seguridad

- Token y token de refresco en el llavero de macOS, sólo con el equipo desbloqueado y sin sincronizar a iCloud.
- Caja de arena con dos permisos: salir a la red y nada más. Se leen enteros en `Centinela.entitlements`.
- Sesión de red efímera: nada de lo que devuelve Sentry se escribe en disco.

### Rendimiento

- El ciclo periódico pide sólo las dos rutas baratas: la serie de errores (378 ms, 937 B) y el estado de uptime (490 ms). La lista de issues (1047 ms, 10,6 KB) se pide únicamente al abrir el panel.
- El temporizador lleva 20 % de tolerancia, para que el sistema junte el despertar con otros.
- Cero peticiones mientras el equipo duerme, y refresco inmediato al despertar.

### Sistema

- Arranque con la sesión vía `SMAppService`, con el estado "falta aprobarlo" tratado aparte en vez de mostrarse como apagado.
- Aviso de versión nueva leyendo la API de releases de GitHub, una vez al día. No se actualiza sola.
- Preferencias con pestañas y ventana "Acerca de".

### Cómo se construye

- SwiftPM más un `Makefile`, sin `.xcodeproj`.
- **No necesita Xcode**: con la toolchain de [swiftly](https://www.swift.org/install/macos/swiftly/) alcanza, y hay un job de CI que lo verifica compilando sin él.
- 45 tests en Swift Testing, incluidos once de integración del inicio de sesión contra un servidor de mentira.
