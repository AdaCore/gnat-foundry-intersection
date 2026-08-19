SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.ONESHELL:

.DEFAULT_GOAL := build-native
.PHONY: help printenv clean generate-config build-native build-target \
        run-native run-target \
        prove prove-report \
        format format-ada format-python check check-ada check-shell check-python \
        check-python-reqs check-python-report \
        check-target-test-parity \
        generate-tests generate-tests-reqs test \
        generate-tests-target build-tests-target test-target smoke-target \
        validate-reqs validate-reqs-corpus \
        trace trace-check trace-check-code trace-check-proof trace-report \
        requirements-doc \
        test-reqs-engine \
        build-tracer test-tracer \
        code-inventory test-inventory inventories \
        report report-pdf test-report-engine \
        setup-community setup-pro reset-hard \
        coverage-rts coverage-instrumentation coverage-build \
        coverage-test all-coverage all-coverage-mixed check-coverage \
        coverage-report-cobertura coverage-report-html coverage-report-text \
        coverage-report-xml

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
PRO_LAL_LIBS  := $(PRO_DIR)/libadalang/lib:$(PRO_DIR)/libadalang/lib64

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

# The setup-* recipes run against this unmodified environment so the previous
# setup's toolchain cannot leak into the new one.
SYSTEM_PATH             := $(PATH)
SYSTEM_GPR_PROJECT_PATH := $(GPR_PROJECT_PATH)
SYSTEM_LIBRARY_PATH     := $(LIBRARY_PATH)
SYSTEM_LD_LIBRARY_PATH  := $(LD_LIBRARY_PATH)

# Compose the detected setup's tools onto PATH. For SETUP=none the
# environment is left alone.
# For SETUP=external, only a locally-installed uv/alr is added.
ifeq ($(SETUP),pro)
export PATH := $(LOCAL_BIN):$(PRO_BINS):$(PATH)
export GPR_PROJECT_PATH := $(PRO_DIR)/libadalang/share/gpr$(if $(GPR_PROJECT_PATH),:$(GPR_PROJECT_PATH))
export LIBRARY_PATH := $(PRO_LAL_LIBS)$(if $(LIBRARY_PATH),:$(LIBRARY_PATH))
export LD_LIBRARY_PATH := $(PRO_LAL_LIBS)$(if $(LD_LIBRARY_PATH),:$(LD_LIBRARY_PATH))
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

# ----------------------------------------------------------------------------
##@ General
# ----------------------------------------------------------------------------

# Sections come from the `##@ <name>` banners below, target descriptions from
# a trailing `## <text>` on the target's own line.
help: ## List the public targets, by section
	@awk 'BEGIN { FS = ":[^#]*##" } \
	     /^##@/ { printf "\n%s\n", substr($$0, 5); next } \
	     /^[a-zA-Z0-9_.-]+:.*##/ { printf "  %-26s  %s\n", $$1, $$2 }' \
	     $(MAKEFILE_LIST)

printenv: ## Print the tool and dependency environment as shell exports
	@$(ALR) printenv
	# `alr printenv` always prints `GPR_PROJECT_PATH`, but only prints `PATH`
	# and `[LD_]LIBRARY_PATH` when the toolchain is `alr`-managed.
	for var in \
	  $(if $(filter pro external,$(SETUP)),PATH LIBRARY_PATH LD_LIBRARY_PATH) \
	  ALIRE_SETTINGS_DIR UV_CACHE_DIR UV_TOOL_DIR UV_TOOL_BIN_DIR UV_PYTHON_INSTALL_DIR;
	do
	  if [ -v "$$var" ]; then echo "export $$var=\"$${!var}\""; fi
	done

# Build products and outputs only. The provisioned toolchain (install/, see
# reset-hard) and Alire's resolved dependencies are left alone.
clean: ## Remove every build product and output
	rm -rf bin obj lib reports $(COVERAGE_LOG) \
	    tests/obj tests/reqs/obj $(TRACER_DIR)/bin $(TRACER_DIR)/obj

# ----------------------------------------------------------------------------
##@ Build and run
# ----------------------------------------------------------------------------

generate-config: ## Generate the `traffic_light` crate's config/ directory
	$(ALR) build --stop-after=generation

build-native: ## Host build (native crate, stub HAL) -> bin/traffic_light
	$(ALR) build

# We have to generate the root `config/` directory explicitly because the
# `traffic_light` crate is not in the Alire closure (but its config is in the
# GPR closure).
#
# Only community builds via `alr` (its gnat_arm_elf dep provides the cross
# compiler); otherwise gprbuild runs directly with the arm-elf tools on PATH.
build-target: generate-config ## QEMU build (sibling crate) -> bin/target/traffic_light
ifeq ($(SETUP),community)
	cd traffic_light_qemu && $(ALR) build -- -XTICK_PERIOD_US=$(TICK_PERIOD_US)
else
	cd traffic_light_qemu && gprbuild -q -P traffic_light_qemu.gpr \
	    -XBUILD_KIND=target -XTICK_PERIOD_US=$(TICK_PERIOD_US)
endif

# Not `alr run`: the QEMU crate emits an identically-named binary under bin/,
# so `alr run` finds two candidates and bails. Reads commands on stdin, emits
# diagnostics on stdout; until Ctrl-C.
run-native: build-native ## Run the host executable
	(stty -echo ; ./bin/traffic_light)

# UART0 (diagnostics) is on your terminal; UART1 (wire-protocol commands) is
# served on 127.0.0.1:$(QEMU_UART1) for an optional client. Quit QEMU with
# Ctrl-A x. Needs qemu-system-arm.
run-target: build-target ## Run the firmware under QEMU (xilinx-zynq-a9)
	scripts/qemu/require-qemu.sh
	qemu-system-arm -M xilinx-zynq-a9 -m 1G -nographic \
	  -serial mon:stdio \
	  -serial tcp:127.0.0.1:$(QEMU_UART1),server,nowait \
	  -kernel bin/target/traffic_light

# ----------------------------------------------------------------------------
##@ Proof
# ----------------------------------------------------------------------------

# The root project sets the scope: `gnatprove -U` analyses its whole tree, and
# src/proof.gpr's is the verification scope COVERAGE_SCOPE also measures
# (README "Verification scope"). Only SPARK_Mode units are analyzed; the rest
# are skipped. gnatprove resolves via the local prefix (on PATH) under
# `alr exec`.
PROOF_SCOPE := $(CURDIR)/src/proof.gpr

prove: generate-config ## SPARK proofs (silver level) across the proof scope
	$(ALR) exec -- gnatprove -P $(PROOF_SCOPE) -U --level=2 \
	    --report=statistics --checks-as-errors=on

# A clean, forced re-analysis so every unit's artifacts come from this one run
# under one switch set, plus proof assumptions and a provenance header. Unlike
# `prove` (the gate), unproved checks do not fail this target — the report
# records them.
GNATPROVE_ARTIFACTS := obj/development/gnatprove

prove-report: generate-config ## Proof run feeding `make report`
	$(ALR) exec -- gnatprove -P $(PROOF_SCOPE) --clean
	$(ALR) exec -- gnatprove -P $(PROOF_SCOPE) -U -f --level=2 \
	    --report=statistics --assumptions --output-header
	$(ALR) exec -- gnatprove --version > $(GNATPROVE_ARTIFACTS)/gnatprove-version.txt

# ----------------------------------------------------------------------------
##@ Format and check
# ----------------------------------------------------------------------------

format: format-ada format-python ## Reformat all sources (Ada and Python)
check: check-ada check-shell check-python check-target-test-parity ## Verify formatting and lint (Ada, shell, Python)

# With pro tools (pro/external), run gnatformat directly: `alr` would fetch
# the community gnat_arm_elf/aunit crates for the nested crates instead.
# Otherwise alr provides those crates (community) or resolves them from the
# configured index (the SETUP=none CI check job).
#
# tests/tests.gpr is a wiring shim with no sources of its own, so the two
# hand-written harnesses under it are named outright: the requirements-based
# tests and the system-level tests are formatted like any other source. Both
# import `aunit`, whose sources belong to that crate and not to this tree, so
# they are the one pair that needs --no-subprojects to stay off them.
format-ada: generate-config ## Reformat all Ada sources in place (gnatformat)
ifneq (,$(filter pro external,$(SETUP)))
	gnatformat -P traffic_light.gpr -U --charset utf-8
	gnatformat -P traffic_light_qemu/traffic_light_qemu.gpr \
	    -XBUILD_KIND=target -U --charset utf-8
	gnatformat -P tests/tests.gpr -U --charset utf-8
	gnatformat -P traffic_light_qemu/tests/target_tests.gpr -U --charset utf-8
	gnatformat -P $(TRACER_DIR)/ada_tracer.gpr -U --charset utf-8
else
	$(ALR) exec -P -- gnatformat -U --charset utf-8
	$(ALR) -C traffic_light_qemu exec -P -- gnatformat -U --charset utf-8
	$(ALR) -C tests exec -P -- gnatformat -U --charset utf-8
	$(ALR) -C traffic_light_qemu/tests exec -P -- gnatformat -U --charset utf-8
	cd $(TRACER_DIR) && $(ALR) exec -P -- gnatformat -U --charset utf-8
endif
	$(TESTS_EXEC) gnatformat -P $(REQS_TESTS) --no-subprojects -U \
	    --charset utf-8
	$(TESTS_EXEC) gnatformat -P $(SYSTEM_TESTS) --no-subprojects -U \
	    --charset utf-8
	$(ALR) exec -- gnatformat -P $(PROOF_SCOPE) --no-subprojects -U \
	    --charset utf-8

# Same split as `format-ada` above.
check-ada: generate-config ## Verify Ada formatting; non-zero if any file would change
ifneq (,$(filter pro external,$(SETUP)))
	gnatformat -P traffic_light.gpr -U --charset utf-8 --check
	gnatformat -P traffic_light_qemu/traffic_light_qemu.gpr \
	    -XBUILD_KIND=target -U --charset utf-8 --check
	gnatformat -P tests/tests.gpr -U --check --charset utf-8
	gnatformat -P traffic_light_qemu/tests/target_tests.gpr -U --check --charset utf-8
	gnatformat -P $(TRACER_DIR)/ada_tracer.gpr -U --check --charset utf-8
else
	$(ALR) exec -P -- gnatformat -U --charset utf-8 --check
	$(ALR) -C traffic_light_qemu exec -P -- gnatformat -U --charset utf-8 --check
	$(ALR) -C tests exec -P -- gnatformat -U --check --charset utf-8
	$(ALR) -C traffic_light_qemu/tests exec -P -- gnatformat -U --check --charset utf-8
	# Temporary: exclude the tracer from the checks: it pulls Libadalang,
	# which slows the CI down.
	# cd $(TRACER_DIR) && $(ALR) exec -P -- gnatformat -U --charset utf-8 --check
endif
	$(TESTS_EXEC) gnatformat -P $(REQS_TESTS) --no-subprojects -U --check \
	    --charset utf-8
	$(TESTS_EXEC) gnatformat -P $(SYSTEM_TESTS) --no-subprojects -U --check \
	    --charset utf-8
	$(ALR) exec -- gnatformat -P $(PROOF_SCOPE) --no-subprojects -U --check \
	    --charset utf-8
	# Commented for now, pending
	#   eng/ide/gnatdoc#189
	#   eng/ide/gnatdoc#190
	#   eng/ide/gnatdoc#191
	# $(ALR) exec -P -- gnatdoc --warnings --style trailing

check-shell: ## Lint the shell scripts (shellcheck)
	find scripts -type f -exec $(UV) tool run --from shellcheck-py shellcheck {} +

# Keep every requirement-citing test on target: a unit left out of the cross
# harness may cite a requirement id only if that id is one of the enumerated
# waivers in the script, and each entry in the ignore list must name a real
# source. Pure shell, so it runs wherever `check` does.
check-target-test-parity: ## Check every requirement-citing test runs on target
	scripts/check-target-test-parity.sh \
	    $(TARGET_TEST_IGNORE) $(CURDIR)/src $(CURDIR)/tests

format-python: ## Format the Python sources (ruff)
	$(UV) --directory "$(REQS_ENGINE)" run ruff format
	$(UV) --directory "$(REPORT_ENGINE)" run --locked ruff format

# Split per engine for CI.
check-python: check-python-reqs check-python-report ## Lint, type-check and format-check Python

# No --locked for reqs: its lock pins a registry the CI runners don't use.
check-python-reqs: ## Python checks for engine/requirements
	$(UV) --directory "$(REQS_ENGINE)" run ruff check
	$(UV) --directory "$(REQS_ENGINE)" run mypy
	$(UV) --directory "$(REQS_ENGINE)" run ruff format --check

check-python-report: ## Python checks for engine/report
	$(UV) --directory "$(REPORT_ENGINE)" run --locked ruff check
	$(UV) --directory "$(REPORT_ENGINE)" run --locked mypy
	$(UV) --directory "$(REPORT_ENGINE)" run --locked ruff format --check

# ----------------------------------------------------------------------------
##@ Test
# ----------------------------------------------------------------------------

# When `SETUP=community`, run in the context of the `tests/` nested crate,
# which provides AUnit through `alr`. Otherwise run in the root crate
# context: AUnit ships with GNAT Pro, and gnattest/gprbuild resolve on PATH.
# Paths passed through $(TESTS_EXEC) are absolute: `-C tests` also moves the
# working directory.
HARNESS := obj/development/gnattest/harness

ifeq ($(SETUP),community)
TESTS_SYNC := $(ALR) -C tests build --stop-after=sync  # Sync `aunit` sources
TESTS_EXEC := $(ALR) -C tests exec --
else
TESTS_SYNC := true
TESTS_EXEC := $(ALR) exec --
endif

# The requirements-based tests (#51): hand-written AUnit fixtures under
# tests/reqs/, one package per LLR file. `--additional-tests` folds them into
# the same generated harness as the skeletons, so they share `make test`.
REQS_TESTS := $(CURDIR)/tests/reqs/reqs_tests.gpr

# `--skeleton-default=fail` makes an unimplemented skeleton fail rather than
# pass: the generated "Test not implemented" assertion reads
# `Gnattest_Generated.Default_Assert_Value`, and defaulting that to True let
# three empty skeletons sit green while claiming requirements (#51).
#
# `--additional-tests` takes a single project: passing it twice keeps only the
# last, silently dropping the first project's suites from the generated main
# suite. tests/reqs/ holds that slot; tests/system/ has its own runner
# (`test-system`).
GNATTEST_FLAGS := --exit-status=on --skeleton-default=fail \
	--additional-tests=$(REQS_TESTS)

generate-tests: generate-config ## Generate/refresh the GNATtest skeletons
	$(TESTS_SYNC)
	$(TESTS_EXEC) gnattest -P $(CURDIR)/traffic_light.gpr $(GNATTEST_FLAGS)

test: generate-tests ## Build and run the AUnit harness
	$(TESTS_EXEC) gprbuild -q -P $(CURDIR)/$(HARNESS)/test_driver.gpr
	$(HARNESS)/test_runner

# The system-level tests: hand-written AUnit fixtures under tests/system/, with
# their own suite and driver. Outside both generated harnesses, and so outside
# the TEST layer and the measured coverage run; tests/system/system_tests.gpr
# says what that buys.
SYSTEM_TESTS := $(CURDIR)/tests/system/system_tests.gpr

test-system: generate-config ## Build and run the system-level tests
	$(TESTS_SYNC)
	$(TESTS_EXEC) gprbuild -q -P $(SYSTEM_TESTS)
	tests/system/bin/test_runner

# ----------------------------------------------------------------------------
# The requirements-based harness: the same `--additional-tests`, with every
# application source ignored, so its generated main suite holds the tests/reqs/
# suites and nothing else. Structural coverage is measured from this harness
# alone.
# ----------------------------------------------------------------------------
REQS_HARNESS := obj/development/gnattest/reqs-harness

# gnattest's `--ignore` takes bare file names and silently drops an entry it
# cannot match, so this list is generated from the tree rather than kept by
# hand.
REQS_IGNORE := $(CURDIR)/obj/development/gnattest/reqs-ignore.txt

# Overwrites the generated driver of the same name; see its header comment.
REQS_DRIVER := $(CURDIR)/tests/reqs/driver/test_runner.adb

# No `--skeleton-default`: this harness generates no skeletons.
GNATTEST_REQS_FLAGS := --exit-status=on \
	--additional-tests=$(REQS_TESTS) \
	--ignore=$(REQS_IGNORE) \
	--harness-dir=$(CURDIR)/$(REQS_HARNESS)

generate-tests-reqs: generate-config ## Generate/refresh the requirements-based harness
	$(TESTS_SYNC)
	mkdir -p $(dir $(REQS_IGNORE))
	find $(CURDIR)/src $(CURDIR)/config \( -name '*.ads' -o -name '*.adb' \) \
	    -printf '%f\n' | sort -u > $(REQS_IGNORE)
	$(TESTS_EXEC) gnattest -P $(CURDIR)/traffic_light.gpr $(GNATTEST_REQS_FLAGS)
	test -f $(CURDIR)/$(REQS_HARNESS)/test_runner.adb  # the file we replace
	cp $(REQS_DRIVER) $(CURDIR)/$(REQS_HARNESS)/test_runner.adb
	scripts/check-reqs-harness.sh \
	    $(CURDIR)/$(REQS_HARNESS)/gnattest_main_suite.adb $(REQS_IGNORE) \
	    $(CURDIR)/tests/reqs/src

# ----------------------------------------------------------------------------
##@ Test on target (arm-eabi firmware under QEMU)
#
# A second gnattest harness, cross-compiled for arm-eabi and run on QEMU's
# xilinx-zynq-a9 machine, over the same test bodies under tests/ that `make
# test` runs natively. Coverage stays native-only (see `all-coverage`).
# ----------------------------------------------------------------------------

TARGET_HARNESS := obj/target/gnattest/harness

# The runtime the firmware itself ships with (src/shared.gpr).
TARGET_RUNTIME := light-tasking-zynq7000

# The only AUnit profile that compiles against light-tasking, which forbids
# exception propagation. Keep in step with traffic_light_qemu/tests/alire.toml.
# Alire path only: see GPRBUILD_TARGET_TEST_SWITCHES.
TARGET_AUNIT_RUNTIME := zfp-cross

# Kept under obj/ so `make clean` reaches it and worktrees stay independent;
# AUnit's default is inside the shared Alire release cache.
TARGET_AUNIT_LIBDIR := $(CURDIR)/obj/target/aunit/lib
TARGET_AUNIT_OBJDIR := $(CURDIR)/obj/target/aunit/obj

# GNATtest units left out of the cross harness; the native harness runs them
# all. A unit qualifies only if its tests are bound to the host profile by
# construction:
#   display.ads  captures standard output into an Ada.Text_IO file
#   sources.ads  redirects standard input from an Ada.Text_IO file
#   timings.ads  measures Delay_For against Ada.Calendar.Clock
# The file holds bare filenames: gnattest drops an entry it cannot match
# without a word, so a comment line survives only by accident -- as would a
# typo, which would silently shorten the on-target run.
#
# Of the three, only timings.ads cites a requirement (llr_6_hal.1), so only it
# needs a waiver in check-target-test-parity.sh.
#
# tests/reqs/ is likewise off target and invisible to that script (#110).
TARGET_TEST_IGNORE := $(CURDIR)/traffic_light_qemu/tests/host_only_sources.txt

QEMU_TEST_TIMEOUT  ?= 120
QEMU_SMOKE_TIMEOUT ?= 60

# The generated skeletons less TARGET_TEST_IGNORE (tests/reqs/ is native-only,
# #110); a mismatch fails `test-target`. Keep in step when adding tests.
QEMU_TEST_EXPECTED ?= 11

# --no-command-line / --no-test-filtering: gnattest's default driver needs
# Ada.Command_Line, GNAT.Command_Line and GNAT.OS_Lib, which bare metal lacks.
GNATTEST_TARGET_SWITCHES := \
    --target=arm-eabi --RTS=$(TARGET_RUNTIME) \
    -XBUILD_KIND=target -XTICK_PERIOD_US=$(TICK_PERIOD_US) \
    --harness-dir=$(CURDIR)/$(TARGET_HARNESS) \
    --ignore=$(TARGET_TEST_IGNORE) \
    --no-command-line --no-test-filtering --exit-status=off

# --target / --RTS on the command line, not just `for Target` / `for Runtime` in
# the project: only the switches put the runtime's own share/gpr on the project
# search path, which is how the pro toolchain's prebuilt AUnit is found. Without
# them a `make setup-pro` tree fails with `imported project file "aunit" not
# found`. The -XAUNIT_* externals below govern the Alire path alone -- the pro
# toolchain's aunit.gpr is Externally_Built and declares no external at all, so
# it ignores them (and is already the zfp flavour these ask for).
GPRBUILD_TARGET_TEST_SWITCHES := \
    --target=arm-eabi --RTS=$(TARGET_RUNTIME) \
    -XBUILD_KIND=target -XTICK_PERIOD_US=$(TICK_PERIOD_US) \
    -XAUNIT_RUNTIME=$(TARGET_AUNIT_RUNTIME) \
    -XAUNIT_PLATFORM=arm-eabi \
    -XAUNIT_LIBDIR=$(TARGET_AUNIT_LIBDIR) \
    -XAUNIT_OBJDIR=$(TARGET_AUNIT_OBJDIR)

# Same community/other split as `generate-tests`, but through the
# traffic_light_qemu/tests crate, which pairs aunit with the arm-eabi toolchain.
generate-tests-target: generate-config ## Generate/refresh the cross harness skeletons
ifeq ($(SETUP),community)
	$(ALR) -C traffic_light_qemu/tests build --stop-after=sync  # Sync `aunit`
	$(ALR) -C traffic_light_qemu/tests exec -- \
	    gnattest -P $(CURDIR)/traffic_light.gpr $(GNATTEST_TARGET_SWITCHES)
else
	gnattest -P traffic_light.gpr $(GNATTEST_TARGET_SWITCHES)
endif

build-tests-target: generate-tests-target ## Cross-build the on-target AUnit harness
ifeq ($(SETUP),community)
	$(ALR) -C traffic_light_qemu/tests exec -- \
	    gprbuild -q -p -P $(CURDIR)/$(TARGET_HARNESS)/test_driver.gpr \
	        $(GPRBUILD_TARGET_TEST_SWITCHES)
else
	gprbuild -q -p -P $(TARGET_HARNESS)/test_driver.gpr \
	    $(GPRBUILD_TARGET_TEST_SWITCHES)
endif

# Needs qemu-system-arm on PATH, as `run-target` does.
test-target: build-tests-target ## Run the AUnit harness on target, under QEMU
	scripts/qemu/test-target.sh \
	    --timeout $(QEMU_TEST_TIMEOUT) \
	    --expected $(QEMU_TEST_EXPECTED) \
	    $(TARGET_HARNESS)/test_runner \
	    obj/target/test-target.log

# Boot the firmware and check it reaches its first complete display frame: the
# only exercise of the target HAL, which the cross harness leaves out.
smoke-target: build-target ## Boot the firmware under QEMU, check its first display frame
	scripts/qemu/run.sh \
	    --console uart0 \
	    --until '^request WEST_SIDE ' \
	    --timeout $(QEMU_SMOKE_TIMEOUT) \
	    --log obj/target/smoke-target.log \
	    bin/target/traffic_light

# ----------------------------------------------------------------------------
##@ Requirements and traceability
# ----------------------------------------------------------------------------

REQS_ENGINE := $(CURDIR)/engine/requirements
REQS_DIR    := $(CURDIR)/requirements
TRACE_CHAIN := $(REQS_DIR)/trace_chain.yaml

# Which layers of the chain `validate-reqs` traces. Defaults to the layers that
# need no Ada toolchain; override to check a narrower part of it.
TRACE_LAYERS := CONOPS,HLR,LLR

# Split out because `make report` gates on this, not on the trace below.
validate-reqs-corpus: ## Check the requirement files (structure, EARS)
	$(UV) --directory "$(REQS_ENGINE)" run reqs validate schema --complete "$(REQS_DIR)/hlr" "$(REQS_DIR)/llr"
	$(UV) --directory "$(REQS_ENGINE)" run reqs validate ears "$(REQS_DIR)/hlr" "$(REQS_DIR)/llr"

validate-reqs: validate-reqs-corpus ## Check the requirement files (structure, EARS, requirements-layer trace)
	$(UV) --directory "$(REQS_ENGINE)" run reqs trace --complete --layers $(TRACE_LAYERS) --chain "$(TRACE_CHAIN)"

trace-check: inventories ## The traceability gate CI runs: exit status is the verdict
	$(UV) --directory "$(REQS_ENGINE)" run reqs trace --complete --chain "$(TRACE_CHAIN)"

trace-check-code: code-inventory ## Trace gate for the workflow's implementation step (CODE + STATIC)
	$(UV) --directory "$(REQS_ENGINE)" run reqs trace --complete --layers CONOPS,HLR,LLR,CODE,STATIC \
	    --allow-unselected test,proof --chain "$(TRACE_CHAIN)"

trace-check-proof: code-inventory ## Trace gate for the workflow's proof step (CODE + STATIC + PROOF)
	$(UV) --directory "$(REQS_ENGINE)" run reqs trace --complete --layers CONOPS,HLR,LLR,CODE,STATIC,PROOF \
	    --allow-unselected test --chain "$(TRACE_CHAIN)"

# Coverage + upward trace per pair, over the whole chain -- including the CODE
# gap `trace-check` excludes.
trace: inventories ## Show the traceability tables for development
	$(UV) --directory "$(REQS_ENGINE)" run reqs trace --complete --format table --chain "$(TRACE_CHAIN)"

# Machine-readable trace report over the whole chain, consumed by `make
# report`. Not a gate: it exits 0 with the gaps recorded in the payload, so
# the verification report can render what is still open.
TRACE_REPORT := $(CURDIR)/reports/trace/trace_report.json

trace-report: inventories ## Write the machine-readable trace report `make report` reads
	$(UV) --directory "$(REQS_ENGINE)" run reqs trace --complete --format json \
	    --chain "$(TRACE_CHAIN)" --output "$(TRACE_REPORT)"

# The requirements as a document, consumed by `make report`: pages the report
# folds into its own tree, plus an index naming each statement's anchor so the
# trace matrices can link to the requirement text. Not a gate either -- gaps
# render into the document as the open items they are.
REQS_DOC := $(CURDIR)/reports/requirements

requirements-doc: inventories ## Render the requirements as a document `make report` reads
	$(UV) --directory "$(REQS_ENGINE)" run reqs document \
	    --chain "$(TRACE_CHAIN)" --out "$(REQS_DOC)"

test-reqs-engine: ## Run the validation engine's own test suite
	$(UV) --directory "$(REQS_ENGINE)" run pytest

# ----------------------------------------------------------------------------
##@ Code inventory (engine/ada_tracer)
# ----------------------------------------------------------------------------

TRACER_DIR := $(CURDIR)/engine/ada_tracer
TRACER     := $(TRACER_DIR)/bin/ada_tracer

# `env -u OS`: CI exports OS=Linux, but dependency projects (libgpr2's
# gpr2_shared.gpr) read `OS` as a Windows_NT/UNIX scenario variable and reject
# other values. `-m2`: checksum-based minimal recompilation, so a restored CI
# cache (fresh timestamps) is not rebuilt from scratch.
build-tracer: ## Build the Ada tracer
ifeq ($(SETUP),community)
	cd $(TRACER_DIR) && env -u OS alr -n build -- -m2
else
	gprbuild -q -P $(TRACER_DIR)/ada_tracer.gpr
endif

# Run the tracer's test suite
test-tracer: build-tracer
	ADA_TRACER="$(TRACER)" $(UV) --directory "$(REQS_ENGINE)" run pytest tests/test_ada_tracer.py

# Run the tracer through `alr exec`, to load the project and its environment.
TRACER_RUN = $(ALR) exec -P -- $(TRACER)

# ----------------------------------------------------------------------------
# The inventories
#
# The TEST and CODE layers of the trace chain read
# obj/analysis/{test,code}_inventory.json, so `trace-check` and `trace` depend on
# this. They are generated fresh, not committed: a committed inventory gone stale
# would report "every test traced" while the tests had moved.
# ----------------------------------------------------------------------------

INVENTORY_DIR  := $(CURDIR)/obj/analysis
CODE_INVENTORY := $(INVENTORY_DIR)/code_inventory.json
TEST_INVENTORY := $(INVENTORY_DIR)/test_inventory.json

# `generate-config`, because traffic_light.gpr imports config/traffic_light_config.gpr
# and the tracer loads the project like any other tool would.
code-inventory: build-tracer generate-config ## Generate the CODE-layer inventory
	mkdir -p "$(INVENTORY_DIR)"
	$(TRACER_RUN) -U -o "$(CODE_INVENTORY)"

DRIVER_PROJECT := $(HARNESS)/test_driver.gpr

# In the community setup aunit reaches the harness project through the `tests`
# nested crate, as for `make test`.
ifeq ($(SETUP),community)
TEST_TRACER_RUN = $(ALR) -C tests exec -- $(TRACER)
else
TEST_TRACER_RUN = $(ALR) exec -- $(TRACER)
endif

# --subproject: only these two projects hold test bodies (never -U).
# --base-dir: report file names relative to the repository root.
test-inventory: build-tracer generate-tests ## Generate the TEST-layer inventory
	mkdir -p "$(INVENTORY_DIR)" "$(CURDIR)/$(HARNESS)/test_obj"
	$(TEST_TRACER_RUN) -P "$(CURDIR)/$(DRIVER_PROJECT)" --base-dir "$(CURDIR)" \
	  --subproject test_traffic_light --subproject reqs_tests \
	  -o "$(TEST_INVENTORY)"

inventories: code-inventory test-inventory ## Generate both inventories

# ----------------------------------------------------------------------------
##@ Verification report
# ----------------------------------------------------------------------------

REPORT_ENGINE := $(CURDIR)/engine/report
REPORT_OUT    := $(CURDIR)/reports/report

# The prerequisites guarantee the report never describes stale artifacts:
# `validate-reqs-corpus` gates on a parseable corpus, `trace-report` regenerates
# the trace matrices from fresh inventories, `requirements-doc` re-renders the
# requirements the matrices link into, `prove-report` is a clean, forced (-f)
# gnatprove run, and `all-coverage` re-runs the requirements-based tests before
# `coverage-report-xml` reads the traces.
# Not `validate-reqs`: trace gaps are open items in the report, not a stop.
REPORT_EVIDENCE := validate-reqs-corpus trace-report requirements-doc prove-report \
                   all-coverage coverage-report-xml

report: $(REPORT_EVIDENCE) ## Regenerate the evidence, then the verification report
	$(UV) --directory "$(REPORT_ENGINE)" run --locked vreport generate \
	    --root "$(CURDIR)" --out "$(REPORT_OUT)"

# rst2pdf -- pure Python, no TeX toolchain needed.
report-pdf: $(REPORT_EVIDENCE) ## Same as `report`, plus a PDF rendering
	$(UV) --directory "$(REPORT_ENGINE)" run --locked vreport generate \
	    --root "$(CURDIR)" --out "$(REPORT_OUT)" --pdf

test-report-engine: ## Run the report engine's own test suite
	$(UV) --directory "$(REPORT_ENGINE)" run --locked pytest

# ----------------------------------------------------------------------------
##@ Setup
#
# Provision all developer tooling locally under install/. Pick one:
#   setup-community: community tools, fetched via Alire (needs internet).
#   setup-pro:       pro tools, from GNAT Tracker downloads staged under
#                    $(PRO_DOWNLOADS), or from PATH if already provided.
# Re-running the other setup target switches between the two; all build/test/
# prove/coverage targets are the same regardless of toolchain.
# ----------------------------------------------------------------------------

# Env vars common to both setup-* targets.
SETUP_ENV := PATH='$(SYSTEM_PATH)' \
    GPR_PROJECT_PATH='$(SYSTEM_GPR_PROJECT_PATH)' \
    LIBRARY_PATH='$(SYSTEM_LIBRARY_PATH)' \
    LD_LIBRARY_PATH='$(SYSTEM_LD_LIBRARY_PATH)' \
    LOCAL_BIN='$(LOCAL_BIN)' \
    ALIRE_SETTINGS_DIR='$(ALIRE_SETTINGS_DIR)' \
    SETUP_MARKER='$(SETUP_MARKER)'

setup-community: ## One-shot: uv, Alire, the community toolchains and tools
	@$(SETUP_ENV) \
	    ALIRE_PREFIX='$(ALIRE_PREFIX)' \
	    scripts/setup/community.sh

# From the staged tarballs or from PATH ($(PRO_TOOLS)). alr is left
# unconfigured: the pro tools resolve on PATH.
setup-pro: ## One-shot: GNAT Pro (native + arm-elf), SPARK Pro, GNAT DAS and Libadalang
	@$(SETUP_ENV) \
	    PRO_DIR='$(PRO_DIR)' \
	    PRO_DOWNLOADS='$(PRO_DOWNLOADS)' \
	    PRO_TOOLS='$(PRO_TOOLS)' \
	    scripts/setup/pro.sh

# Staged pro downloads ($(PRO_DOWNLOADS)), sources and build artifacts (bin/,
# obj/) are untouched.
reset-hard: ## Remove install/ entirely -- everything the setup-* targets installed
	@echo "Removing locally-installed setup tooling at $(INSTALL_DIR) ..."
	rm -rf "$(INSTALL_DIR)"
	echo "Done. Staged tarballs, sources and build artifacts left untouched."

# ----------------------------------------------------------------------------
##@ Coverage
# ----------------------------------------------------------------------------

# Where the traces will be emitted
GNATCOV_TRACES := $(CURDIR)/obj/gnatcov-traces

# The RTS project
GNATCOV_RTS := $(CURDIR)/obj/gnatcov-rts/share/gpr/gnatcov_rts.gpr

# The coverage reports directory
COVERAGE_REPORTS := $(CURDIR)/reports/coverage

# Which harness `coverage-test` instruments, builds and runs.
COVERAGE_HARNESS      := $(REQS_HARNESS)
COVERAGE_HARNESS_DEPS := generate-tests-reqs

# The verification scope (README "Verification scope"): the controller, and
# not the HAL simulator, the composition or the entry point that wire it.
COVERAGE_SCOPE := --projects core --projects types

$(COVERAGE_REPORTS):
	mkdir -p $(COVERAGE_REPORTS)

# The `file:line:col:` findings of a text report, above the exempted regions.
COVERAGE_FINDINGS = awk '/^== 3\. EXEMPTED REGIONS ==/ {exit} {print}' \
    $(COVERAGE_REPORTS)/report.txt | grep -e '^.*:[0-9]\+:[0-9]\+: .*$$'

# "quiet" all-in-one coverage, for use by agents.
COVERAGE_LOG := coverage.log
all-coverage: ## Instrument, build, run the requirements-based tests, print the violations
	@$(MAKE) coverage-instrumentation coverage-build coverage-test > $(COVERAGE_LOG) 2>&1 || (cat $(COVERAGE_LOG) ; exit 1)
	@$(MAKE) coverage-report-text >> $(COVERAGE_LOG) 2>&1 || (cat $(COVERAGE_LOG) ; exit 1)
	@$(COVERAGE_FINDINGS) || true

check-coverage: ## Fail if the coverage report holds a non-exempted violation
	@test -f $(COVERAGE_REPORTS)/report.txt || { \
	    echo "$(COVERAGE_REPORTS)/report.txt: no report -- run make all-coverage" ; \
	    exit 1 ; }
	@if $(COVERAGE_FINDINGS) ; then \
	    echo "" ; \
	    echo "coverage gate: the findings above are uncovered code in scope." ; \
	    echo "Close them with routines under tests/reqs/, or -- if no" ; \
	    echo "requirement governs the code -- raise that as the finding." ; \
	    exit 1 ; \
	fi
	@echo "coverage gate: no non-exempted violations"

all-coverage-mixed: ## Same, from the full test suite -> reports/coverage-mixed/
	@$(MAKE) all-coverage \
	    COVERAGE_HARNESS=$(HARNESS) \
	    COVERAGE_HARNESS_DEPS=generate-tests \
	    GNATCOV_TRACES=$(CURDIR)/obj/gnatcov-traces-mixed \
	    COVERAGE_REPORTS=$(CURDIR)/reports/coverage-mixed \
	    COVERAGE_LOG=coverage-mixed.log

# Named alias for the file rule below.
coverage-rts: $(GNATCOV_RTS) ## Provision the local gnatcov RTS

# Local gnatcov RTS
$(GNATCOV_RTS):
	$(ALR) exec -- gnatcov setup --prefix=$(CURDIR)/obj/gnatcov-rts

coverage-instrumentation: generate-config $(GNATCOV_RTS) ## Create the instrumented sources
	$(ALR) exec -P2 -- gnatcov instrument \
		--level=stmt+mcdc $(COVERAGE_SCOPE) \
	    --runtime-project $(GNATCOV_RTS)

coverage-build: ## Build the instrumented sources
	$(ALR) build -- -g -O0 -m2 \
	    --src-subdirs=gnatcov-instr \
	    --implicit-with=$(GNATCOV_RTS)

coverage-test: $(COVERAGE_HARNESS_DEPS) ## Instrument, build and run the tests for coverage
	rm -rf $(GNATCOV_TRACES)
	mkdir -p $(GNATCOV_TRACES)
	$(TESTS_EXEC) gnatcov instrument \
	    -P $(CURDIR)/$(COVERAGE_HARNESS)/test_driver.gpr \
		--level=stmt+mcdc $(COVERAGE_SCOPE) \
	    --runtime-project $(GNATCOV_RTS)
	$(TESTS_EXEC) gprbuild -p -P $(CURDIR)/$(COVERAGE_HARNESS)/test_driver.gpr \
	    -g -O0 -m2 \
	    --src-subdirs=gnatcov-instr \
	    --implicit-with=$(GNATCOV_RTS)
	export GNATCOV_TRACE_FILE=$(GNATCOV_TRACES)/ && \
	    $(COVERAGE_HARNESS)/test_runner

coverage-report-cobertura: $(COVERAGE_REPORTS) ## Coverage report: cobertura XML
	export GNATCOV_TRACE_FILE=$(GNATCOV_TRACES)/ && \
	$(ALR) exec -P2 -- gnatcov coverage \
	    --level=stmt+mcdc $(COVERAGE_SCOPE) \
		--annotate=cobertura \
		--output-dir $(COVERAGE_REPORTS)/cobertura \
		$(GNATCOV_TRACES)/

coverage-report-html: $(COVERAGE_REPORTS) ## Coverage report: HTML (not with community gnatcov)
	export GNATCOV_TRACE_FILE=$(GNATCOV_TRACES)/ && \
	$(ALR) exec -P2 -- gnatcov coverage \
	    --level=stmt+mcdc $(COVERAGE_SCOPE) \
		--annotate=html \
		--output-dir $(COVERAGE_REPORTS)/html \
		$(GNATCOV_TRACES)/

coverage-report-text: $(COVERAGE_REPORTS) ## Coverage report: text
	export GNATCOV_TRACE_FILE=$(GNATCOV_TRACES)/ && \
	$(ALR) exec -P2 -- gnatcov coverage \
	    --level=stmt+mcdc $(COVERAGE_SCOPE) \
		--annotate=report \
		-o $(COVERAGE_REPORTS)/report.txt \
		$(GNATCOV_TRACES)/

# Full fidelity: per-obligation stmt/decision/MC/DC, per-scope metrics,
# exemption justifications. Like the other coverage-report-* targets, this
# consumes whatever traces are under $(GNATCOV_TRACES) — run `coverage-test`
# (or `all-coverage`) first for fresh ones. The exact command is recorded next
# to the XML, only after a zero exit.
GNATCOV_XML_CMD = gnatcov coverage --level=stmt+mcdc $(COVERAGE_SCOPE) --annotate=xml \
    --output-dir $(COVERAGE_REPORTS)/xml $(GNATCOV_TRACES)/
coverage-report-xml: $(COVERAGE_REPORTS) ## Coverage report: machine-readable XML, parsed by `make report`
	export GNATCOV_TRACE_FILE=$(GNATCOV_TRACES)/ && \
	$(ALR) exec -P2 -- $(GNATCOV_XML_CMD)
	echo "$(GNATCOV_XML_CMD)" > $(COVERAGE_REPORTS)/xml/gnatcov-command.txt
	$(ALR) exec -- gnatcov --version > $(COVERAGE_REPORTS)/xml/gnatcov-version.txt
