.DEFAULT_GOAL := build-native
.PHONY: build-native build-target run-native run-target prove \
        format format-ada check check-ada

# TCP port for QEMU's UART1 (wire-protocol command channel).
QEMU_UART1 ?= 5556

# Host build (native crate, stub HAL) -> bin/traffic_light.
build-native:
	alr build

# Bare-metal arm-eabi QEMU build (sibling crate) -> bin/qemu_mps2/traffic_light.
build-target:
	cd traffic_light_qemu && alr build

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
# gnatprove resolves via $HOME/.alire/bin under `alr exec`.
prove:
	alr exec -- gnatprove -P traffic_light.gpr --level=2 --report=statistics --checks-as-errors=on

# Format / check aggregators. For now they just delegate to the Ada targets;
# add format-<lang> / check-<lang> prerequisites here as more land.
format: format-ada
check: check-ada

# Reformat all Ada sources of the default project in place (gnatformat).
format-ada:
	alr exec -- gnatformat -P traffic_light.gpr -U --charset utf-8

# Verify formatting without editing; exits non-zero if any file would change.
check-ada:
	alr exec -- gnatformat -P traffic_light.gpr -U --charset utf-8 --check
