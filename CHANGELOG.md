# Cambios

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/).
Versionado semántico.

## [Sin publicar]

### Agregado

- Barra de menús con conteo de errores, chispa de la ventana elegida y aviso de caída de uptime.
- Panel con issues sin resolver, issues por revisar (`is:for_review`) y últimos releases.
- Token en el llavero de macOS, con detección de token sobre-privilegiado (si puede leer `/audit-logs/`, no es de sólo lectura).
- Arranque con la sesión vía `SMAppService`, con el estado `.requiresApproval` tratado aparte.
- Liquid Glass en los botones del pie en macOS 26+, detrás de `#available`.
- Suite de 15 tests en Swift Testing sobre fixtures anonimizadas.
- CI: compila y testea en `macos-26` con la toolchain de Xcode y con `swiftly`; dos guardias de higiene del repositorio, ambos probados inyectando la violación.
