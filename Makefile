.DEFAULT_GOAL := help
SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
export PATH := $(CURDIR)/.artifacts/godot-bin:$(PATH)
GODOT_BIN ?= godot
.PHONY: help install lint test build check artifact-smoke dev stop clean
help:
	@echo 'make install  Install the manifest-verified Godot binary and export templates'
	@echo 'make check    Verify package controls, runner controls, addon behavior and shipping output'
install:
	GODOT_ARCHIVE_DIR="$(CURDIR)/.artifacts/godot-downloads" GODOT_BINARY_DIR="$(CURDIR)/.artifacts/godot-bin" INSTALL_TEMPLATES=true bash tools/setup_godot.sh
lint dev stop:
	@echo '$@: unsupported: addon requires a consuming Godot project; verification is make check'
test:
	python3 tools/package_test.py
	GODOT_BIN="$(GODOT_BIN)" bash tests/test.sh --self-test
	GODOT_BIN="$(GODOT_BIN)" bash tests/test.sh
build:
	mkdir -p dist
	python3 tools/package.py build dist/@aviorstudio_gd-audio.zip | tee dist/package-evidence.txt
	sha256sum dist/@aviorstudio_gd-audio.zip > dist/package.sha256
artifact-smoke: build
	python3 tools/package_smoke.py dist/@aviorstudio_gd-audio.zip --godot "$(GODOT_BIN)" --web-output dist/web-smoke
check: test build artifact-smoke
clean:
	python3 -c 'import shutil; [shutil.rmtree(path, ignore_errors=True) for path in (".artifacts", "dist")]'
