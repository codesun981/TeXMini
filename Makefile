APP_NAME := TeXMini
BUNDLE := build/$(APP_NAME).app

all: build

build:
	@chmod +x build.sh
	@./build.sh

run: build
	@echo "==> 启动 $(APP_NAME)..."
	@open $(BUNDLE)

install: build
	@echo "==> 正在安装 $(APP_NAME) 到 /Applications/..."
	@rm -rf /Applications/$(APP_NAME).app
	@cp -R $(BUNDLE) /Applications/
	@echo "==> 安装成功！您可以在访达或启动台中打开 $(APP_NAME)。"

test:
	@chmod +x tests/run_tests.sh
	@./tests/run_tests.sh

clean:
	@rm -rf build sample/*.aux sample/*.log sample/*.synctex.gz sample/*.fls sample/*.fdb_latexmk sample/*.pdf
	@echo "==> 清理完成。"

.PHONY: all build run install test clean
