SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.ONESHELL:

.DEFAULT_GOAL := build-native
.PHONY: printenv generate-config build-native build-target run-native run-target \
        prove \
        format format-ada format-python check check-ada check-shell check-python \
        generate-tests test \
        validate-reqs trace test-reqs-engine \
        setup-community setup-pro reset-hard \
        coverage-rts coverage-instrumentation coverage-build \
        coverage-test all-coverage \
        coverage-report-cobertura coverage-report-html coverage-report-text

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
# Everything the setup-* targets install lands under install/, so reset-hard
# is a complete wipe. Locally-installed tools are preferred; anything missing
# is expected on PATH.
INSTALL_DIR  := $(CURDIR)/install
LOCAL_BIN    := $(INSTALL_DIR)/bin
ALIRE_PREFIX := $(INSTALL_DIR)/alire/prefix
UV_DATA_DIR  := $(INSTALL_DIR)/uv

# A pre-defined ALIRE_SETTINGS_DIR takes precedence over the local default.
ALIRE_SETTINGS_DIR ?= $(INSTALL_DIR)/alire/settings

# --- Pro tooling layout (make setup-pro) ------------------------------------
# The pro products are installed from GNAT Tracker downloads (the product
# tarballs, or the zipfiles wrapping them) staged under $(PRO_DOWNLOADS),
# each into its own prefix under install/pro/. The staging dir is kept
# outside install/ so reset-hard does not delete the downloads.
PRO_DIR       := $(INSTALL_DIR)/pro
PRO_DOWNLOADS ?= $(CURDIR)/pro-downloads
PRO_BINS      := $(PRO_DIR)/gnatpro/bin:$(PRO_DIR)/arm-elf/bin:$(PRO_DIR)/spark/bin:$(PRO_DIR)/gnatdas/bin

# Force the setup-pro source: make setup-pro PRO_TOOLS=install (staged
# downloads) or PRO_TOOLS=external (tools on PATH); empty auto-detects.
PRO_TOOLS ?=

# Prefer the locally-installed binaries; fall back to PATH if absent.
ALR := $(if $(wildcard $(LOCAL_BIN)/alr),$(LOCAL_BIN)/alr -n,alr -n)
UV  := $(if $(wildcard $(LOCAL_BIN)/uv),$(LOCAL_BIN)/uv,uv)

# Which setup provisioned install/, as recorded in $(SETUP_MARKER) by the
# last setup-* target that ran: "pro", "community", "external" (pro tools
# from PATH), or "none" (no local setup; tools are expected on PATH already).
SETUP_MARKER := $(INSTALL_DIR)/setup
SETUP := $(or $(filter pro community external,$(shell cat '$(SETUP_MARKER)' 2>/dev/null)),none)

# The setup-* recipes run against this unmodified PATH so the previous
# setup's toolchain cannot leak into the new one.
SYSTEM_PATH := $(PATH)

# Compose the detected setup's tools onto PATH. For SETUP=none the
# environment is left alone.
# For SETUP=external, only a locally-installed uv/alr is added.
ifeq ($(SETUP),pro)
export PATH := $(LOCAL_BIN):$(PRO_BINS):$(PATH)
else ifeq ($(SETUP),community)
export PATH := $(LOCAL_BIN):$(ALIRE_PREFIX)/bin:$(PATH)
else ifeq ($(SETUP),external)
export PATH := $(LOCAL_BIN):$(PATH)
endif
ifneq ($(SETUP),none)
export ALIRE_SETTINGS_DIR
endif

# Once uv is installed locally, keep its cache, managed Python, and installed
# tools under install/ so reset-hard wipes them too.
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
#
# Only community builds via `alr` (its gnat_arm_elf dep provides the cross
# compiler); otherwise gprbuild runs directly with the arm-elf tools on PATH.
build-target: generate-config
ifeq ($(SETUP),community)
	cd traffic_light_qemu && $(ALR) build -- -XTICK_PERIOD_US=$(TICK_PERIOD_US)
else
	cd traffic_light_qemu && gprbuild -q -P traffic_light_qemu.gpr \
	    -XBUILD_KIND=target -XTICK_PERIOD_US=$(TICK_PERIOD_US)
endif

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

# Reformat all Ada sources of the three projects in place (gnatformat).
# With pro tools (pro/external), run gnatformat directly: `alr` would fetch
# the community gnat_arm_elf/aunit crates for the nested crates instead.
# Otherwise alr provides those crates (community) or resolves them from the
# configured index (the SETUP=none CI check job).
format-ada: generate-config
ifneq (,$(filter pro external,$(SETUP)))
	gnatformat -P traffic_light.gpr -U --charset utf-8
	gnatformat -P traffic_light_qemu/traffic_light_qemu.gpr \
	    -XBUILD_KIND=target -U --charset utf-8
	gnatformat -P tests/tests.gpr -U --charset utf-8
else
	$(ALR) exec -P -- gnatformat -U --charset utf-8
	$(ALR) -C traffic_light_qemu exec -P -- gnatformat -U --charset utf-8
	$(ALR) -C tests exec -P -- gnatformat -U --charset utf-8
endif

# Verify formatting without editing; exits non-zero if any file would change.
# Same split as `format-ada` above.
check-ada: generate-config
ifneq (,$(filter pro external,$(SETUP)))
	gnatformat -P traffic_light.gpr -U --charset utf-8 --check
	gnatformat -P traffic_light_qemu/traffic_light_qemu.gpr \
	    -XBUILD_KIND=target -U --charset utf-8 --check
	gnatformat -P tests/tests.gpr -U --check --charset utf-8
else
	$(ALR) exec -P -- gnatformat -U --charset utf-8 --check
	$(ALR) -C traffic_light_qemu exec -P -- gnatformat -U --charset utf-8 --check
	$(ALR) -C tests exec -P -- gnatformat -U --check --charset utf-8
endif
	# Commented for now, pending
	#   eng/ide/gnatdoc#189
	#   eng/ide/gnatdoc#190
	#   eng/ide/gnatdoc#191
	# $(ALR) exec -P -- gnatdoc --warnings --style trailing

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

# Build and run the AUnit harness.
#
# When `SETUP=community`, run in the context of the `tests/` nested crate,
# which provides AUnit through `alr`. Otherwise run in the root crate
# context: AUnit ships with GNAT Pro, and gnattest/gprbuild resolve on PATH.
HARNESS := obj/development/gnattest/harness

# Generate/refresh GNATtest skeletons.
generate-tests: generate-config
ifeq ($(SETUP),community)
	$(ALR) -C tests build --stop-after=sync  # Sync `aunit` sources
	$(ALR) -C tests exec -- gnattest -P ../traffic_light.gpr --exit-status=on
else
	$(ALR) exec -P -- gnattest --exit-status=on
endif

test: generate-tests
ifeq ($(SETUP),community)
	$(ALR) -C tests exec -- gprbuild -q -P ../$(HARNESS)/test_driver.gpr
else
	$(ALR) exec -- gprbuild -q -P $(HARNESS)/test_driver.gpr
endif
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
# Setup: provision all developer tooling locally under install/. Pick one:
#   setup-community: community tools, fetched via Alire (needs internet).
#   setup-pro:       pro tools, from GNAT Tracker downloads staged under
#                    $(PRO_DOWNLOADS), or from PATH if already provided.
# Re-running the other setup target switches between the two; all build/test/
# prove/coverage targets are the same regardless of toolchain.
# ----------------------------------------------------------------------------

# Env vars common to both setup-* targets.
SETUP_ENV := PATH='$(SYSTEM_PATH)' \
    LOCAL_BIN='$(LOCAL_BIN)' \
    ALIRE_SETTINGS_DIR='$(ALIRE_SETTINGS_DIR)' \
    SETUP_MARKER='$(SETUP_MARKER)'

# One-shot: uv, Alire, the community GNAT toolchains, and
# gnattest/gnatcov/gnatformat/gnatprove.
setup-community:
	@$(SETUP_ENV) \
	    ALIRE_PREFIX='$(ALIRE_PREFIX)' \
	    scripts/setup/community.sh

# One-shot: GNAT Pro (native + arm-elf), SPARK Pro and GNAT DAS, from the
# staged tarballs or from PATH ($(PRO_TOOLS)). alr is left unconfigured:
# the pro tools resolve on PATH.
setup-pro:
	@$(SETUP_ENV) \
	    PRO_DIR='$(PRO_DIR)' \
	    PRO_DOWNLOADS='$(PRO_DOWNLOADS)' \
	    PRO_TOOLS='$(PRO_TOOLS)' \
	    scripts/setup/pro.sh

# ----------------------------------------------------------------------------
# Reset: remove everything the setup-* targets installed.
# ----------------------------------------------------------------------------

# Remove install/ entirely. Staged pro downloads ($(PRO_DOWNLOADS)), sources
# and build artifacts (bin/, obj/) are untouched.
reset-hard:
	@echo "Removing locally-installed setup tooling at $(INSTALL_DIR) ..."
	rm -rf "$(INSTALL_DIR)"
	echo "Done. Staged tarballs, sources and build artifacts left untouched."

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

# Provision the local gnatcov RTS (named alias for the file rule below).
coverage-rts: $(GNATCOV_RTS)

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

# Instrument, build and run the tests for coverage. Same community/other
# split as `test` above.
coverage-test: generate-tests
	rm -rf $(GNATCOV_TRACES)
	mkdir -p $(GNATCOV_TRACES)
ifeq ($(SETUP),community)
	$(ALR) -C tests exec -- gnatcov instrument -P ../$(HARNESS)/test_driver.gpr \
		--level=stmt+mcdc \
	    --runtime-project $(GNATCOV_RTS)
	$(ALR) -C tests exec -- gprbuild -P ../$(HARNESS)/test_driver.gpr \
	    -g -O0 -m2 \
	    --src-subdirs=gnatcov-instr \
	    --implicit-with=$(GNATCOV_RTS)
else
	$(ALR) exec -- gnatcov instrument -P $(HARNESS)/test_driver.gpr \
		--level=stmt+mcdc \
	    --runtime-project $(GNATCOV_RTS)
	$(ALR) exec -- gprbuild -P $(HARNESS)/test_driver.gpr \
	    -g -O0 -m2 \
	    --src-subdirs=gnatcov-instr \
	    --implicit-with=$(GNATCOV_RTS)
endif
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
all-coverage:
	@make coverage-instrumentation coverage-build coverage-test > $(COVERAGE_LOG) 2>&1 || (cat $(COVERAGE_LOG) ; exit 1)
	@make coverage-report-text >> $(COVERAGE_LOG) 2>&1 || (cat $(COVERAGE_LOG) ; exit 1)
	@grep -e '^.*:[0-9]\+:[0-9]\+: .*$$' $(COVERAGE_REPORTS)/report.txt || true
