# Centinela se construye con SwiftPM y el paquete de aplicación se arma acá, a mano.
#
# No hay `.xcodeproj` a propósito. Un `project.pbxproj` es un archivo generado de decenas de
# miles de líneas que ninguna persona revisa en un diff y que entra en conflicto con sólo
# abrirlo. Para una aplicación de un binario y sin extensiones, `swift build` más unas líneas
# de `Makefile` hacen lo mismo y se leen enteras.

# El compilador se resuelve al BINARIO REAL de la toolchain, no al `swift` del PATH.
#
# Con swiftly instalado, `~/.swiftly/bin/swift` es un proxy que decide la toolchain en tiempo
# de ejecución. Bajo `make` esa decisión sale distinta que bajo una shell interactiva: SwiftPM
# termina compilando el manifiesto con `/Library/Developer/CommandLineTools/usr/bin/swiftc`,
# cuyo `PackageDescription` no conoce `swiftLanguageMode`, y `Package.swift` falla a parsear
# con un error que no menciona nada de esto. Preguntarle a swiftly dónde vive la toolchain y
# usar esa ruta saca al proxy del medio.
SWIFTLY   := $(shell command -v swiftly 2>/dev/null)
TOOLCHAIN := $(if $(SWIFTLY),$(shell $(SWIFTLY) use --print-location 2>/dev/null))
SWIFT     ?= $(if $(TOOLCHAIN),$(TOOLCHAIN)/usr/bin/swift,swift)

APP           := Centinela
BUNDLE_ID     := cl.bioalergia.centinela
VERSION       ?= $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' | grep . || echo 0.0.0)
BUILD         ?= $(shell git rev-list --count HEAD 2>/dev/null || echo 1)
CONFIG        ?= release
BUILD_DIR     := .build/$(CONFIG)
APP_DIR       := build/$(APP).app
# Sin identidad de firma se firma ad-hoc. Alcanza para correrlo en la máquina donde se
# construyó; para repartirlo hace falta un Developer ID (ver README, "Distribución").
IDENTITY      ?= -

.PHONY: build app run test lint clean instalar toolchain

toolchain:
	@echo "swift: $(SWIFT)"
	@$(SWIFT) --version | head -1

build:
	$(SWIFT) build -c $(CONFIG)

test:
	$(SWIFT) test

# swiftlint necesita `sourcekitdInProc.framework`, que sólo busca dentro de Xcode. Con la
# toolchain de swiftly hay que apuntárselo a mano o se cae con un `Fatal error` de dlopen.
SOURCEKIT := $(if $(TOOLCHAIN),$(TOOLCHAIN)/usr/lib)

lint:
	@command -v swiftlint >/dev/null 2>&1 || { \
		echo "swiftlint no está instalado: brew install swiftlint"; \
		echo "(esto ANTES se saltaba en silencio, y así llegaron 80 violaciones a CI)"; \
		exit 1; \
	}
	DYLD_FRAMEWORK_PATH="$(SOURCEKIT)" swiftlint lint --quiet --strict

app: build
	rm -rf $(APP_DIR)
	mkdir -p $(APP_DIR)/Contents/MacOS $(APP_DIR)/Contents/Resources
	cp $(BUILD_DIR)/$(APP) $(APP_DIR)/Contents/MacOS/$(APP)
	sed -e 's/__VERSION__/$(VERSION)/' -e 's/__BUILD__/$(BUILD)/' \
		Resources/Info.plist > $(APP_DIR)/Contents/Info.plist
	# `swift build` deja el paquete de recursos del objetivo al lado del binario; si existe,
	# tiene que viajar dentro del bundle o `Bundle.module` no lo encuentra en ejecución.
	@if [ -d "$(BUILD_DIR)/$(APP)_$(APP).bundle" ]; then \
		cp -R "$(BUILD_DIR)/$(APP)_$(APP).bundle" $(APP_DIR)/Contents/Resources/; \
	fi
	# Las localizaciones viajan como carpetas `.lproj` dentro de Resources. Es lo que hace que
	# el sistema titule la ventana de preferencias en español.
	cp -R Resources/*.lproj $(APP_DIR)/Contents/Resources/
	cp Resources/Centinela.icns $(APP_DIR)/Contents/Resources/
	codesign --force --options runtime --entitlements Centinela.entitlements \
		--sign "$(IDENTITY)" $(APP_DIR)
	@echo "Listo: $(APP_DIR) (versión $(VERSION), build $(BUILD), firma '$(IDENTITY)')"

run: app
	open $(APP_DIR)

instalar: app
	rm -rf /Applications/$(APP).app
	cp -R $(APP_DIR) /Applications/
	@echo "Instalado en /Applications/$(APP).app"

clean:
	rm -rf .build build
