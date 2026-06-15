.DEFAULT_GOAL := build-native
.PHONY: build-native build-target prove

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
