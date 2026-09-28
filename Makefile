APP_NAME := TeXMini
BUNDLE := build/$(APP_NAME).app

all: build

build:
	@chmod +x build.sh
	@./build.sh

run: build
	@echo "==> 启动 $(APP_NAME)..."
	@open $(BUNDLE)

# 开发循环：退出正在运行的旧版本 → 编译 → 启动新版本。
# 直接 open 只会把旧进程切到前台，不会加载新二进制，所以必须先杀掉。
dev:
	@if pgrep -xq $(APP_NAME); then \
		echo "==> 退出正在运行的 $(APP_NAME)..."; \
		osascript -e 'tell application "$(APP_NAME)" to quit' >/dev/null 2>&1 || pkill -x $(APP_NAME) || true; \
		for i in 1 2 3 4 5 6 7 8 9 10; do pgrep -xq $(APP_NAME) || break; sleep 0.3; done; \
		pgrep -xq $(APP_NAME) && { echo "==> $(APP_NAME) 未退出（可能有未保存的更改对话框），请先处理再重试"; exit 1; } || true; \
	fi
	@$(MAKE) --no-print-directory build
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

package:
	@bash scripts/package_release.sh

clean:
	@rm -rf build
	@echo "==> 清理完成。"

.PHONY: all build run dev install test package clean
