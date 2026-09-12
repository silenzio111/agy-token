#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="AgyToken.app"
APP_DIR="$ROOT_DIR/$APP_NAME"
NATIVE_DIR="$ROOT_DIR/NativeApp"
ICON_FILE="$NATIVE_DIR/AppIcon.icns"
ICON_SCRIPT="$NATIVE_DIR/generate_app_icon.swift"
LAUNCHER_BIN="$NATIVE_DIR/AgyToken"

cd "$ROOT_DIR"

printf '🚀 开始构建 AgyToken 原生 macOS 应用程序...\n'

# 1. 确保图标生成
if [ ! -f "$ICON_FILE" ] || [ "${1:-}" = "--rebuild-icon" ]; then
    printf '🎨 生成矢量高清 AppIcon.icns...\n'
    swift "$ICON_SCRIPT" "$ROOT_DIR"
else
    printf '🎨 使用已有 AppIcon.icns: %s\n' "$ICON_FILE"
fi

# 2. 编译 SwiftUI 原生 Mach-O 应用程序
printf '⚡ 编译 SwiftUI 原生应用程序 (Mach-O)...\n'
SDK_PATH="$(xcrun --show-sdk-path)"
swiftc \
    -O \
    -sdk "$SDK_PATH" \
    -target "$(uname -m)-apple-macosx13.0" \
    -parse-as-library \
    -framework SwiftUI \
    -framework AppKit \
    -framework Charts \
    "$NATIVE_DIR/Sources/Models.swift" \
    "$NATIVE_DIR/Sources/TokenPredictor.swift" \
    "$NATIVE_DIR/Sources/LiveTelemetry.swift" \
    "$NATIVE_DIR/Sources/AgyTokenViewModel.swift" \
    "$NATIVE_DIR/Sources/Views/"*.swift \
    "$NATIVE_DIR/Sources/AgyTokenApp.swift" \
    -o "$LAUNCHER_BIN"

# 3. 组装 .app Bundle 目录结构
printf '📦 组装 macOS App Bundle 结构...\n'
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

# 4. 复制配置文件与二进制
cp "$NATIVE_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$LAUNCHER_BIN" "$APP_DIR/Contents/MacOS/AgyToken"
chmod +x "$APP_DIR/Contents/MacOS/AgyToken"

# 5. 复制扫描后端资源
cp "$ICON_FILE" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$ROOT_DIR/token_scanner.py" "$APP_DIR/Contents/Resources/token_scanner.py"
cp "$ROOT_DIR/model_prices.json" "$APP_DIR/Contents/Resources/model_prices.json"

# 6. 清理可能存在的多余元数据
xattr -cr "$APP_DIR" 2>/dev/null || true

# 7. 进行原生代码签名 (Ad-Hoc 本地签名)
if command -v codesign >/dev/null 2>&1; then
    printf '🔏 执行 macOS 代码签名 (Ad-hoc)...\n'
    codesign --force --deep --sign - "$APP_DIR" >/dev/null
    codesign -vvv --deep --strict "$APP_DIR"
fi

printf '\n✨ 构建成功！已生成原生应用：\n'
printf '👉 %s\n\n' "$APP_DIR"
printf '💡 启动方式：\n'
printf '   1. 直接双击当前目录中的 "%s"\n' "$APP_NAME"
printf '   2. 命令行执行: open %q\n' "$APP_DIR"
