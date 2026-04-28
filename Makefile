BOARD     ?= nucleo_h563zi
BUILD_DIR ?= build

build:
	alr exec -- west build -b $(BOARD) -d $(BUILD_DIR)

pristine:
	alr exec -- west build -b $(BOARD) -d $(BUILD_DIR) --pristine

flash:
	alr exec -- west flash -d $(BUILD_DIR)

clean:
	rm -rf $(BUILD_DIR)
