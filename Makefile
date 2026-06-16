SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.ONESHELL:

.DEFAULT_GOAL := build-native
.PHONY: printenv build-native build-target run-native run-target prove \
        format format-ada check check-ada \
        generate-tests-pro test-pro generate-tests-community test-community \
        setup-community setup-uv setup-alire setup-toolchains \
        setup-tools reset-hard \
        coverage-rts coverage-instrumentation coverage-build \
        coverage-test-pro coverage-report

# TCP port for QEMU's UART1 (wire-protocol command channel).
QEMU_UART1 ?= 5556

# --- Local tooling layout ---------------------------------------------------
# The locally-installed alr/uv under install/ are preferred when present;
# otherwise we fall back to whatever is on PATH. Setup *output* (toolchains +
# installed binaries) always lands under install/ regardless of which binary
# is used, so reset-hard is a complete wipe.
TOOLS_DIR      := $(CURDIR)/install
LOCAL_BIN      := $(TOOLS_DIR)/bin
ALIRE_SETTINGS := $(TOOLS_DIR)/alire/settings
ALIRE_PREFIX   := $(TOOLS_DIR)/alire/prefix
UV_DATA_DIR    := $(TOOLS_DIR)/uv

# Prefer the locally-installed binaries; fall back to PATH if absent.
ALR := $(if $(wildcard $(LOCAL_BIN)/alr),$(LOCAL_BIN)/alr -n,alr -n)
UV  := $(if $(wildcard $(LOCAL_BIN)/uv),$(LOCAL_BIN)/uv,uv)

# Once the local Alire settings exist (i.e. setup has run), point every alr
# invocation at the local toolchains + installed-tool prefix. Before that, we
# leave the environment alone so a system alr keeps using its own ~/.alire.
ifneq ($(wildcard $(ALIRE_SETTINGS)),)
export ALIRE_SETTINGS_DIR := $(ALIRE_SETTINGS)
export PATH := $(LOCAL_BIN):$(ALIRE_PREFIX)/bin:$(PATH)
endif

# Likewise for uv (the analogue of ALIRE_SETTINGS_DIR + --prefix): once it is
# installed locally, keep its cache, managed Python, and installed tools under
# install/ so reset-hard wipes them too. A system uv keeps its own defaults
# (~/.cache/uv, ~/.local/share/uv) until setup runs.
ifneq ($(wildcard $(LOCAL_BIN)/uv),)
export UV_CACHE_DIR          := $(UV_DATA_DIR)/cache
export UV_TOOL_DIR           := $(UV_DATA_DIR)/tools
export UV_TOOL_BIN_DIR       := $(LOCAL_BIN)
export UV_PYTHON_INSTALL_DIR := $(UV_DATA_DIR)/python
endif

# Print environment for tools/dependencies
printenv:
	@$(ALR) printenv
	# We don't need to print `PATH` because it is already printed by `alr printenv`.
	for var in ALIRE_SETTINGS_DIR UV_CACHE_DIR UV_TOOL_DIR UV_TOOL_BIN_DIR UV_PYTHON_INSTALL_DIR; do
	  if [ -v "$$var" ]; then echo "export $$var=\"$${!var}\""; fi
	done

# ----------------------------------------------------------------------------
# Build / run / prove / format
# ----------------------------------------------------------------------------

# Host build (native crate, stub HAL) -> bin/traffic_light.
build-native:
	$(ALR) build

# Bare-metal arm-eabi QEMU build (sibling crate) -> bin/qemu_mps2/traffic_light.
build-target:
	cd traffic_light_qemu && $(ALR) build

# Run the host executable. (Not `alr run`: the QEMU crate emits an
# identically-named binary under bin/, so `alr run` finds two candidates and
# bails.) Reads commands on stdin, emits diagnostics on stdout; until Ctrl-C.
run-native: build-native
	./bin/traffic_light

# Run the firmware under QEMU (mps2-an385). UART0 (diagnostics) is on your
# terminal; UART1 (wire-protocol commands) is served on 127.0.0.1:$(QEMU_UART1)
# for an optional client. Quit QEMU with Ctrl-A x. Needs qemu-system-arm.
run-target: build-target
	qemu-system-arm -M mps2-an385 -cpu cortex-m3 -nographic \
	  -serial mon:stdio \
	  -serial tcp:127.0.0.1:$(QEMU_UART1),server,nowait \
	  -kernel bin/qemu_mps2/traffic_light

# SPARK proofs (silver level: absence of run-time errors) across the default
# project. Only SPARK_Mode units are analyzed; the rest are skipped.
# gnatprove resolves via the local prefix (on PATH) under `alr exec`.
prove:
	$(ALR) exec -- gnatprove -P traffic_light.gpr --level=2 --report=statistics --checks-as-errors=on

# Format / check aggregators. For now they just delegate to the Ada targets;
# add format-<lang> / check-<lang> prerequisites here as more land.
format: format-ada
check: check-ada

# Remove build products and outputs
clean:
	rm -rf obj reports

# Reformat all Ada sources of the default project in place (gnatformat).
format-ada:
	$(ALR) exec -- gnatformat -P traffic_light.gpr -U --charset utf-8

# Verify formatting without editing; exits non-zero if any file would change.
check-ada:
	$(ALR) exec -- gnatformat -P traffic_light.gpr -U --charset utf-8 --check

# Generate/refresh GNATtest skeletons
generate-tests-pro:
	$(ALR) build --stop-after=generation     # Generate `config/`
	$(ALR) exec -- gnattest -P traffic_light.gpr

# Build and run the AUnit harness
HARNESS := obj/development/gnattest/harness
test-pro: generate-tests-pro
	$(ALR) exec -- gprbuild -P $(HARNESS)/test_driver.gpr
	$(HARNESS)/test_runner

# To use community tools, we run from inside `tests/` to pick up `alr`-managed
# `gnattest_bin` and `aunit`.
generate-tests-community:
	$(ALR) -C tests build --stop-after=sync  # Sync `aunit` sources
	$(ALR) build --stop-after=generation     # Generate `config/`
	$(ALR) -C tests exec -- gnattest -P ../traffic_light.gpr

test-community: generate-tests-community
	$(ALR) -C tests exec -- gprbuild -P ../$(HARNESS)/test_driver.gpr
	$(HARNESS)/test_runner

# ----------------------------------------------------------------------------
# Community setup: provision all developer tooling locally under install/
# ----------------------------------------------------------------------------

# One-shot: provision the full toolchain locally under install/ — uv, Alire,
# the GNAT toolchains, and gnattest/gnatcov/gnatprove. Everything a contributor
# needs to build, test, and prove.
setup-community: setup-uv setup-alire setup-toolchains setup-tools
	@echo ""
	echo "=== setup-community complete ==="
	echo "Local tooling installed under $(TOOLS_DIR):"
	echo "  uv / uvx                    -> $(LOCAL_BIN) (or PATH uv if pre-existing)"
	echo "  alr                         -> $(LOCAL_BIN) (or PATH alr if pre-existing)"
	echo "  GNAT toolchains             -> $(ALIRE_SETTINGS)"
	echo "  gnattest/gnatcov/gnatprove  -> $(ALIRE_PREFIX)/bin"
	echo ""
	echo "The Makefile uses these automatically. To run the tools from your"
	echo "shell, add to your profile:"
	echo "  export PATH=\"$(LOCAL_BIN):$(ALIRE_PREFIX)/bin:\$$PATH\""
	echo "  export ALIRE_SETTINGS_DIR=\"$(ALIRE_SETTINGS)\""

# uv: install the latest official release from GitHub, locally into install/bin.
setup-uv:
	@if [ -x "$(LOCAL_BIN)/uv" ]; then
	  echo "uv already installed locally ($(LOCAL_BIN)/uv) — skipping."
	  exit 0
	fi
	if command -v uv >/dev/null 2>&1; then
	  echo "uv found on PATH ($$(command -v uv)) — skipping local install."
	  exit 0
	fi
	echo "Installing uv locally into $(LOCAL_BIN) ..."
	mkdir -p "$(LOCAL_BIN)"
	os=$$(uname -s); arch=$$(uname -m)
	case "$$arch" in
	  arm64|aarch64) uarch=aarch64 ;;
	  x86_64|amd64)  uarch=x86_64 ;;
	  *) echo "Unsupported architecture: $$arch" >&2; exit 1 ;;
	esac
	case "$$os" in
	  Linux)  triple="$$uarch-unknown-linux-gnu" ;;
	  *) echo "Unsupported OS: $$os" >&2; exit 1 ;;
	esac
	url="https://github.com/astral-sh/uv/releases/latest/download/uv-$$triple.tar.gz"
	echo "Downloading $$url"
	tmp=$$(mktemp -d)
	curl -fsSL "$$url" -o "$$tmp/uv.tar.gz"
	tar -xzf "$$tmp/uv.tar.gz" -C "$$tmp"
	mv "$$tmp/uv-$$triple/uv" "$$tmp/uv-$$triple/uvx" "$(LOCAL_BIN)/"
	rm -rf "$$tmp"
	echo "uv installed: $$($(LOCAL_BIN)/uv --version)"

# Alire: install the latest official release from GitHub, locally into install/bin.
setup-alire:
	@if [ -x "$(LOCAL_BIN)/alr" ]; then
	  echo "alr already installed locally ($(LOCAL_BIN)/alr) — skipping."
	  exit 0
	fi
	if command -v alr >/dev/null 2>&1; then
	  echo "alr found on PATH ($$(command -v alr)) — skipping local install."
	  exit 0
	fi
	echo "Installing Alire locally into $(LOCAL_BIN) ..."
	mkdir -p "$(LOCAL_BIN)"
	os=$$(uname -s); arch=$$(uname -m)
	case "$$arch" in
	  arm64|aarch64) aarch=aarch64 ;;
	  x86_64|amd64)  aarch=x86_64 ;;
	  *) echo "Unsupported architecture: $$arch" >&2; exit 1 ;;
	esac
	case "$$os" in
	  Linux)  aos=linux ;;
	  *) echo "Unsupported OS: $$os" >&2; exit 1 ;;
	esac
	url=$$( (curl -fsSL https://api.github.com/repos/alire-project/alire/releases/latest \
	  | grep -o "\"browser_download_url\": \"[^\"]*bin-$$aarch-$$aos[^\"]*\"" \
	  | grep -o 'https://[^"]*' | head -1) || true )
	if [ -z "$$url" ]; then
	  echo "Could not find an Alire release asset for $$aarch-$$aos" >&2
	  exit 1
	fi
	echo "Downloading $$url"
	tmp=$$(mktemp -d)
	curl -fsSL "$$url" -o "$$tmp/alr.zip"
	unzip -q "$$tmp/alr.zip" -d "$$tmp/alr"
	mv "$$tmp/alr/bin/alr" "$(LOCAL_BIN)/alr"
	chmod +x "$(LOCAL_BIN)/alr"
	rm -rf "$$tmp"
	echo "alr installed: $$($(LOCAL_BIN)/alr --version)"

# Select the GNAT toolchains needed by the demo, into the local settings dir.
setup-toolchains: setup-alire
	@ALR="$(LOCAL_BIN)/alr"; [ -x "$$ALR" ] || ALR=alr
	export ALIRE_SETTINGS_DIR="$(ALIRE_SETTINGS)"
	mkdir -p "$(ALIRE_SETTINGS)"
	if "$$ALR" -n toolchain 2>/dev/null | grep -q gnat_arm_elf \
	   && "$$ALR" -n toolchain 2>/dev/null | grep -q gnat_native \
	   && "$$ALR" -n toolchain 2>/dev/null | grep -q gprbuild; then
	  echo "Toolchains (gnat_arm_elf, gnat_native, gprbuild) already selected — skipping."
	  exit 0
	fi
	echo "Selecting toolchains: gnat_arm_elf gnat_native gprbuild ..."
	"$$ALR" -n toolchain --select gnat_arm_elf gnat_native gprbuild

# Install the gnattest, gnatcov, and gnatprove binaries into the local prefix.
setup-tools: setup-alire
	@ALR="$(LOCAL_BIN)/alr"; [ -x "$$ALR" ] || ALR=alr
	export ALIRE_SETTINGS_DIR="$(ALIRE_SETTINGS)"
	mkdir -p "$(ALIRE_PREFIX)"
	need=""
	[ -x "$(ALIRE_PREFIX)/bin/gnattest" ]  || need="$$need gnattest_bin"
	[ -x "$(ALIRE_PREFIX)/bin/gnatcov" ]   || need="$$need gnatcov_bin"
	[ -x "$(ALIRE_PREFIX)/bin/gnatprove" ] || need="$$need gnatprove"
	if [ -z "$$need" ]; then
	  echo "gnattest + gnatcov + gnatprove already installed — skipping."
	  exit 0
	fi
	echo "Installing:$$need ..."
	"$$ALR" -n install --prefix="$(ALIRE_PREFIX)" $$need

# ----------------------------------------------------------------------------
# Reset: remove everything the setup-* targets installed.
# ----------------------------------------------------------------------------

# Remove all locally-installed setup tooling (uv, alr, toolchains, gnattest /
# gnatcov / gnatprove). Source and build artifacts (bin/, obj/) are untouched.
reset-hard:
	@echo "Removing locally-installed setup tooling at $(TOOLS_DIR) ..."
	rm -rf "$(TOOLS_DIR)"
	echo "Done. Source and build artifacts left untouched."

####################
# Coverage support #
####################

# Where the traces will be emitted
GNATCOV_TRACES := $$(pwd)/obj/gnatcov-traces

# The RTS project
GNATCOV_RTS := $$(pwd)/obj/gnatcov-rts/share/gpr/gnatcov_rts.gpr

# Local gnatcov RTS
coverage-rts:
	$(ALR) exec -- gnatcov setup --prefix=$$(pwd)/obj/gnatcov-rts

# Create the instrumented sources
coverage-instrumentation:
	$(ALR) exec -P2 -- gnatcov instrument \
		--level=stmt+mcdc \
	    --runtime-project $(GNATCOV_RTS)

# Build the intrumented sources
coverage-build:
	$(ALR) build -- -g -O0 \
	    --src-subdirs=gnatcov-instr \
	    --implicit-with=$(GNATCOV_RTS)

# Instrument, build and run the tests for coverage
coverage-test-pro: generate-tests-pro
	rm -rf $(GNATCOV_TRACES)
	mkdir -p $(GNATCOV_TRACES)
	$(ALR) exec -- gnatcov instrument -P $(HARNESS)/test_driver.gpr \
		--level=stmt+mcdc \
	    --runtime-project $(GNATCOV_RTS)
	$(ALR) exec -- gprbuild -P $(HARNESS)/test_driver.gpr \
	    -g -O0 \
	    --src-subdirs=gnatcov-instr \
	    --implicit-with=$(GNATCOV_RTS)
	export GNATCOV_TRACE_FILE=$(GNATCOV_TRACES)/ && \
	    $(HARNESS)/test_runner

# Instrument, build and run the tests for coverage
coverage-test-community: generate-tests-community
	rm -rf $(GNATCOV_TRACES)
	mkdir -p $(GNATCOV_TRACES)
	$(ALR) -C tests exec -- gnatcov instrument -P $(HARNESS)/test_driver.gpr \
		--level=stmt+mcdc \
	    --runtime-project $(GNATCOV_RTS)
	$(ALR) -C tests exec -- gprbuild -P $(HARNESS)/test_driver.gpr \
	    -g -O0 \
	    --src-subdirs=gnatcov-instr \
	    --implicit-with=$(GNATCOV_RTS)
	export GNATCOV_TRACE_FILE=$(GNATCOV_TRACES)/ && \
	    $(HARNESS)/test_runner

# Generate a cobertura coverage report (XML) from the traces.
coverage-report-cobertura:
	mkdir -p reports/coverage
	export GNATCOV_TRACE_FILE=$(GNATCOV_TRACES)/ && \
	$(ALR) exec -P2 -- gnatcov coverage \
	    --level=stmt+mcdc \
		--annotate=cobertura \
		--output-dir reports/coverage/cobertura \
		$(GNATCOV_TRACES)/

# Generate the coverage HTML report (not available with community gnatcov)
coverage-report-html:
	export GNATCOV_TRACE_FILE=$(GNATCOV_TRACES)/ && \
	$(ALR) exec -P2 -- gnatcov coverage \
	    --level=stmt+mcdc \
		--annotate=html \
		--output-dir reports/coverage/html \
		$(GNATCOV_TRACES)/

# Generate the coverage text report
coverage-report-text:
	export GNATCOV_TRACE_FILE=$(GNATCOV_TRACES)/ && \
	$(ALR) exec -P2 -- gnatcov coverage \
	    --level=stmt+mcdc \
		--annotate=report \
		-o reports/coverage/report.txt \
		$(GNATCOV_TRACES)/
