#!/usr/bin/env bash
# 往 watched.tex 末尾追加一行，模拟外部程序（git checkout、Dropbox、另一编辑器）修改文件。
cd "$(dirname "$0")"
echo "% externally appended at $(date +%H:%M:%S)" >> watched.tex
echo "appended one line to watched.tex"
