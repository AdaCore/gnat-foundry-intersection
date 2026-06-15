.DEFAULT_GOAL := build-native
.PHONY: build-native build-target

# Host build (native crate, stub HAL) -> bin/main.
build-native:
	alr build

# Bare-metal arm-eabi QEMU build (sibling crate) -> bin/qemu_mps2/main.
build-target:
	cd traffic_light_qemu && alr build
