# Centinela se construye con SwiftPM y el paquete de aplicación se arma acá, a mano.
#
# No hay `.xcodeproj` a propósito. Un `project.pbxproj` es un archivo generado de decenas de
# miles de líneas que ninguna persona revisa en un diff y que entra en conflicto con sólo
# abrirlo. Para una aplicación de un binario y sin extensiones, `swift build` más doce líneas
# de `Makefile` hacen lo mismo y se leen enteras.

APP           := Centinela
BUNDLE_ID     := cl.bioalergia.centinela
VERSION       ?= $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' | grep . || echo 0.0.0)
BUILD         ?= $(shell git rev-list --count HEAD 2>/dev/null || echo 1)
CONFIG        ?= release
BUILD_DIR     := .build/$(CONFIG)
APP_DIR       := build/$(APP).app
# Sin identidad de firma se firma ad-hoc. Es suficiente para correrlo en la máquina donde se
# construyó; para repartirlo hace falta un Developer ID (ver README, "Distribución").
IDENTITY      ?= -

.PHONY: build app run test lint clean instalar

build:
	swift build -c $(CONFIG)

test:
	swift test

lint:
	@command -v swiftlint >/dev/null 2>&1 && swiftlint --strict || echo "swiftlint no está instalado; se omite"

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
