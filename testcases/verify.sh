#!/usr/bin/env bash
# 不经过 GUI，直接用 latexmk 跑一遍所有用例，核对"应该成功的成功、应该失败的失败"。
# 用途：改了编译器 / 日志解析后快速回归；也验证测试文件本身没写错。
cd "$(dirname "$0")"
export PATH="/Library/TeX/texbin:$PATH"

pass=0; fail=0
run() { # run <expect:ok|err> <engineflag> <dir> <file> [extra args]
  local expect=$1 flag=$2 dir=$3 file=$4; shift 4
  local out
  ( cd "$dir" && latexmk "$flag" -synctex=1 -interaction=nonstopmode -halt-on-error -file-line-error "$@" "$file" >/dev/null 2>&1 )
  local code=$?
  local got=ok; [ $code -ne 0 ] && got=err
  if [ "$got" = "$expect" ]; then pass=$((pass+1)); printf "  ✓ %-55s %s\n" "$dir/$file" "$got"
  else fail=$((fail+1)); printf "  ✗ %-55s expected %s, got %s (exit %d)\n" "$dir/$file" "$expect" "$got" "$code"; fi
}

run ok  -pdf      01-basic-article main.tex
run ok  -xelatex  02-chinese-ctex report.tex
run ok  -pdf      03-multi-file-project main.tex
for f in undefined-command missing-dollar unclosed-env missing-input missing-package missing-graphic two-errors; do
  run err -pdf 04-compile-errors $f.tex
done
run ok  -pdf      05-warnings-and-badboxes warnings.tex
run ok  -pdf      06-bibliography/bibtex-natbib paper.tex
run ok  -pdf      06-bibliography/biblatex-biber paper.tex
run ok  -pdf      07-engines-and-magic-comments pdflatex-default.tex
run ok  -xelatex  07-engines-and-magic-comments xelatex-magic.tex
run err -pdf      07-engines-and-magic-comments xelatex-magic.tex
run ok  -lualatex 07-engines-and-magic-comments lualatex-magic.tex
run ok  -xelatex  07-engines-and-magic-comments fontspec-heuristic.tex
run ok  -pdf      07-engines-and-magic-comments/root-magic main.tex
run ok  -pdf      08-shell-escape write18.tex
run ok  -pdf      08-shell-escape write18.tex -shell-escape
run ok  -pdf      08-shell-escape minted.tex
run ok  -pdf      08-shell-escape minted.tex -shell-escape
run ok  -pdf      09-figures-and-dragdrop with-graphicx.tex
run ok  -pdf      10-large-document big.tex
run ok  -pdf      11-encoding-and-edge-cases latin1.tex
run ok  -pdf      11-encoding-and-edge-cases crlf.tex
run err -pdf      11-encoding-and-edge-cases fragment-no-documentclass.tex
run err -pdf      11-encoding-and-edge-cases empty.tex
run ok  -pdf      12-beamer slides.tex
run ok  -pdf      16-spelling prose.tex

echo "$pass passed, $fail failed"
[ $fail -eq 0 ]
