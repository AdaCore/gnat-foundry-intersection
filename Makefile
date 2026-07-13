SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.ONESHELL:

.DEFAULT_GOAL := build-native
.PHONY: printenv generate-config build-native build-target run-native run-target \
        prove \
        format format-ada format-python check check-ada check-shell check-python \
        generate-tests-pro test-pro generate-tests-community test-community \
        validate-reqs trace test-reqs-engine \
        setup-community reset-hard \
        coverage-rts coverage-instrumentation coverage-build \
        coverage-test-pro coverage-report

# TCP port for QEMU's UART1 (wire-protocol command channel).
QEMU_UART1 ?= 5556

# Wall-clock microseconds per logical 1 ms tick in the QEMU firmware (see
# src/hal.gpr and the src/hal/common/timings-tick_config__*.ads profile specs
# it selects via its Naming package). Valid values are 1000, 300, 10. 1000 =
# faithful real time; 300 runs the requirements suite faster by compensating
# upstream QEMU's ~3.33x-slow timer.
#   make build-target TICK_PERIOD_US=300
TICK_PERIOD_US ?= 1000

# --- Local tooling layout ---------------------------------------------------
# The locally-installed alr/uv under install/ are preferred when present;
# otherwise we fall back to whatever is on PATH. Setup *output* (toolchains +
# installed binaries) always lands under install/ regardless of which binary
# is used, so reset-hard is a complete wipe.
INSTALL_DIR    := $(CURDIR)/install
LOCAL_BIN      := $(INSTALL_DIR)/bin
ALIRE_SETTINGS := $(INSTALL_DIR)/alire/settings
ALIRE_PREFIX   := $(INSTALL_DIR)/alire/prefix
UV_DATA_DIR    := $(INSTALL_DIR)/uv

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

# Explicitly generate the `config/` directory for the `traffic_light` crate.
generate-config:
	$(ALR) build --stop-after=generation

# Host build (native crate, stub HAL) -> bin/traffic_light.
build-native:
	$(ALR) build

# QEMU build (sibling crate) -> bin/target/traffic_light.
#
# We have to generate the root `config/` directory explicitly because the
# `traffic_light` crate is not in the Alire closure (but its config is in the
# GPR closure).
build-target: generate-config
	cd traffic_light_qemu && $(ALR) build -- -XTICK_PERIOD_US=$(TICK_PERIOD_US)

# Run the host executable. (Not `alr run`: the QEMU crate emits an
# identically-named binary under bin/, so `alr run` finds two candidates and
# bails.) Reads commands on stdin, emits diagnostics on stdout; until Ctrl-C.
run-native: build-native
	./bin/traffic_light

# Run the firmware under QEMU (xilinx-zynq-a9). UART0 (diagnostics) is on your
# terminal; UART1 (wire-protocol commands) is served on 127.0.0.1:$(QEMU_UART1)
# for an optional client. Quit QEMU with Ctrl-A x. Needs qemu-system-arm.
run-target: build-target
	qemu-system-arm -M xilinx-zynq-a9 -m 1G -nographic \
	  -serial mon:stdio \
	  -serial tcp:127.0.0.1:$(QEMU_UART1),server,nowait \
	  -kernel bin/target/traffic_light

# SPARK proofs (silver level: absence of run-time errors) across the default
# project. Only SPARK_Mode units are analyzed; the rest are skipped.
# gnatprove resolves via the local prefix (on PATH) under `alr exec`.
prove:
	$(ALR) exec -P -- gnatprove -U --level=2 --report=statistics --checks-as-errors=on

# Format / check aggregators.
format: format-ada format-python
check: check-ada check-shell check-python

# Remove build products and outputs
clean:
	rm -rf obj reports

# Reformat all Ada sources of the default project in place (gnatformat).
format-ada: generate-config
	$(ALR) exec -P -- gnatformat -U --charset utf-8
	$(ALR) -C traffic_light_qemu exec -P -- gnatformat -U --charset utf-8
	$(ALR) -C tests exec -P -- gnatformat -U --charset utf-8

# Verify formatting without editing; exits non-zero if any file would change.
check-ada: generate-config
	$(ALR) exec -P -- gnatformat -U --charset utf-8 --check
	$(ALR) -C traffic_light_qemu exec -P -- gnatformat -U --charset utf-8 --check
	$(ALR) -C tests exec -P -- gnatformat -U --check --charset utf-8

# Lint shell scripts with shellcheck.
check-shell:
	find scripts -type f -exec $(UV) tool run --from shellcheck-py shellcheck {} +

# Format Python sources.
format-python:
	$(UV) --directory "$(REQS_ENGINE)" run ruff format

# Lint, type-check and verify formatting of Python.
check-python:
	$(UV) --directory "$(REQS_ENGINE)" run ruff check
	$(UV) --directory "$(REQS_ENGINE)" run mypy
	$(UV) --directory "$(REQS_ENGINE)" run ruff format --check

# Generate/refresh GNATtest skeletons
generate-tests-pro: generate-config
	$(ALR) exec -P -- gnattest --exit-status=on

# Build and run the AUnit harness
HARNESS := obj/development/gnattest/harness
test-pro: generate-tests-pro
	$(ALR) exec -- gprbuild -q -P $(HARNESS)/test_driver.gpr
	$(HARNESS)/test_runner

# To use community tools, we run from inside `tests/` to pick up `alr`-managed
# `gnattest_bin` and `aunit`.
generate-tests-community: generate-config
	$(ALR) -C tests build --stop-after=sync  # Sync `aunit` sources
	$(ALR) -C tests exec -- gnattest -P ../traffic_light.gpr --exit-status=on

test-community: generate-tests-community
	$(ALR) -C tests exec -- gprbuild -P ../$(HARNESS)/test_driver.gpr
	$(HARNESS)/test_runner

# ----------------------------------------------------------------------------
# Requirements validation
# ----------------------------------------------------------------------------

REQS_ENGINE := $(CURDIR)/engine/requirements
REQS_DIR    := $(CURDIR)/requirements

# Check the requirement files for structural validity, EARS syntax, and
# traceability across the chain (every node covered by / traced to a neighbour,
# or waived / derived). --complete makes an uncovered node a hard error.
validate-reqs:
	$(UV) --directory "$(REQS_ENGINE)" run reqs validate schema --complete "$(REQS_DIR)/hlr"  # "$(REQS_DIR)/llr"
	$(UV) --directory "$(REQS_ENGINE)" run reqs validate ears "$(REQS_DIR)/hlr"  # "$(REQS_DIR)/llr"
	$(UV) --directory "$(REQS_ENGINE)" run reqs trace --complete --chain "$(REQS_DIR)/trace_chain.yaml"

# Show the traceability tables for development (coverage + upward trace per pair).
# `validate-reqs` runs the same check as the hard CI gate.
trace:
	$(UV) --directory "$(REQS_ENGINE)" run reqs trace --format table --chain "$(REQS_DIR)/trace_chain.yaml"

# Run the validation engine's own test suite.
test-reqs-engine:
	$(UV) --directory "$(REQS_ENGINE)" run pytest

# ----------------------------------------------------------------------------
# Community setup: provision all developer tooling locally under install/
# ----------------------------------------------------------------------------

# One-shot: provision the full toolchain locally under install/ — uv, Alire,
# the GNAT toolchains, and gnattest/gnatcov/gnatformat/gnatprove. Everything a
# contributor needs to build, test, and prove.
setup-community:
	@LOCAL_BIN='$(LOCAL_BIN)' \
	    ALIRE_SETTINGS_DIR='$(ALIRE_SETTINGS)' \
	    ALIRE_PREFIX='$(ALIRE_PREFIX)' \
	    scripts/setup/community.sh

# ----------------------------------------------------------------------------
# Reset: remove everything the setup-* targets installed.
# ----------------------------------------------------------------------------

# Remove all locally-installed setup tooling (uv, alr, toolchains, gnattest /
# gnatcov / gnatformat / gnatprove). Source and build artifacts (bin/, obj/)
# are untouched.
reset-hard:
	@echo "Removing locally-installed setup tooling at $(INSTALL_DIR) ..."
	rm -rf "$(INSTALL_DIR)"
	echo "Done. Source and build artifacts left untouched."

####################
# Coverage support #
####################

# Where the traces will be emitted
GNATCOV_TRACES := $$(pwd)/obj/gnatcov-traces

# The RTS project
GNATCOV_RTS := $$(pwd)/obj/gnatcov-rts/share/gpr/gnatcov_rts.gpr

# The coverage reports directory
COVERAGE_REPORTS := $$(pwd)/reports/coverage

$(COVERAGE_REPORTS):
	mkdir -p $(COVERAGE_REPORTS)

# Local gnatcov RTS
$(GNATCOV_RTS):
	$(ALR) exec -- gnatcov setup --prefix=$$(pwd)/obj/gnatcov-rts

# Create the instrumented sources
coverage-instrumentation: $(GNATCOV_RTS)
	$(ALR) exec -P2 -- gnatcov instrument \
		--level=stmt+mcdc \
	    --runtime-project $(GNATCOV_RTS)

# Build the intrumented sources
coverage-build:
	$(ALR) build -- -g -O0 -m2 \
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
	    -g -O0 -m2 \
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
	    -g -O0 -m2 \
	    --src-subdirs=gnatcov-instr \
	    --implicit-with=$(GNATCOV_RTS)
	export GNATCOV_TRACE_FILE=$(GNATCOV_TRACES)/ && \
	    $(HARNESS)/test_runner

# Generate a cobertura coverage report (XML) from the traces.
coverage-report-cobertura: $(COVERAGE_REPORTS)
	export GNATCOV_TRACE_FILE=$(GNATCOV_TRACES)/ && \
	$(ALR) exec -P2 -- gnatcov coverage \
	    --level=stmt+mcdc \
		--annotate=cobertura \
		--output-dir $(COVERAGE_REPORTS)/cobertura \
		$(GNATCOV_TRACES)/

# Generate the coverage HTML report (not available with community gnatcov)
coverage-report-html: $(COVERAGE_REPORTS)
	export GNATCOV_TRACE_FILE=$(GNATCOV_TRACES)/ && \
	$(ALR) exec -P2 -- gnatcov coverage \
	    --level=stmt+mcdc \
		--annotate=html \
		--output-dir $(COVERAGE_REPORTS)/html \
		$(GNATCOV_TRACES)/

# Generate the coverage text report
coverage-report-text: $(COVERAGE_REPORTS)
	export GNATCOV_TRACE_FILE=$(GNATCOV_TRACES)/ && \
	$(ALR) exec -P2 -- gnatcov coverage \
	    --level=stmt+mcdc \
		--annotate=report \
		-o $(COVERAGE_REPORTS)/report.txt \
		$(GNATCOV_TRACES)/

# "quiet" all-in-one coverage, for use by agents: create a
# coverage report and print only the errors, if any.
COVERAGE_LOG := coverage.log
all-coverage-pro:
	@make coverage-instrumentation coverage-build coverage-test-pro > $(COVERAGE_LOG) 2>&1 || (cat $(COVERAGE_LOG) ; exit 1)
	@make coverage-report-text >> $(COVERAGE_LOG) 2>&1 || (cat $(COVERAGE_LOG) ; exit 1)
	@grep -e '^.*:[0-9]\+:[0-9]\+: .*$$' $(COVERAGE_REPORTS)/report.txt || true