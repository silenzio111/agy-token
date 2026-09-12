#!/bin/bash
cd "$(dirname "$0")"

# 启动原生 SwiftUI 应用程序
open "AgyToken.app"

# 自动关闭启动时弹出的终端窗口，保持桌面清爽
osascript -e 'tell application "Terminal" to close first window' >/dev/null 2>&1 &
