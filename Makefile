.DEFAULT_GOAL := build-native
.PHONY: build-native build-target prove \
        format format-ada check check-ada

# Host build (native crate, stub HAL) -> bin/main.
build-native:
	alr build

# Bare-metal arm-eabi QEMU build (sibling crate) -> bin/qemu_mps2/main.
build-target:
	cd traffic_light_qemu && alr build

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
