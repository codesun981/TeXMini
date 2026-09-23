#!/usr/bin/env bash
# 只更新修改时间不改内容：编辑器不应弹任何提示。
cd "$(dirname "$0")"
touch watched.tex
echo "touched watched.tex (content unchanged)"
