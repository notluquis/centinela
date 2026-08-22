# Cambios

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/).
Versionado semántico.

## [Sin publicar]

### Agregado

- Inicio de sesión con el flujo de dispositivo de OAuth 2.0 (RFC 8628), verificado contra sentry.io, con el identificador de cliente incluido y renovación automática bajo el 10 % de vida restante.
- Aviso de versión nueva leyendo la API de releases de GitHub, una vez al día.
- Pestaña "Acerca de" con versión, enlaces y búsqueda manual de actualizaciones.
- Ícono generado desde código (`Tools/generar-icono.swift`).
- Localización en español del paquete, para que el sistema no titule la ventana de preferencias en inglés.
- Liquid Glass en los botones del pie, dentro de un `GlassEffectContainer`, siguiendo la guía oficial de Apple.

- Barra de menús con conteo de errores, chispa de la ventana elegida y aviso de caída de uptime.
- Panel con issues sin resolver, issues por revisar (`is:for_review`) y últimos releases.
- Token en el llavero de macOS, con detección de token sobre-privilegiado (si puede leer `/audit-logs/`, no es de sólo lectura).
- Arranque con la sesión vía `SMAppService`, con el estado `.requiresApproval` tratado aparte.
- Liquid Glass en los botones del pie en macOS 26+, detrás de `#available`.
- Suite de 15 tests en Swift Testing sobre fixtures anonimizadas.
- CI: compila y testea en `macos-26` con la toolchain de Xcode y con `swiftly`; dos guardias de higiene del repositorio, ambos probados inyectando la violación.
