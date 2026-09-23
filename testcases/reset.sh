#!/usr/bin/env bash
# 把 testcases/ 恢复到干净状态：删除编译产物、拖放复制的图片、shell-escape 生成物，并还原被脚本改过的文件。
set -e
cd "$(dirname "$0")"

find . -type f \( -name '*.aux' -o -name '*.log' -o -name '*.fls' -o -name '*.fdb_latexmk' \
  -o -name '*.synctex.gz' -o -name '*.synctex' -o -name '*.out' -o -name '*.toc' -o -name '*.lof' -o -name '*.lot' \
  -o -name '*.bbl' -o -name '*.blg' -o -name '*.bcf' -o -name '*.run.xml' -o -name '*.nav' -o -name '*.snm' \
  -o -name '*.vrb' -o -name '*.idx' -o -name '*.ilg' -o -name '*.ind' -o -name '*.xdv' \) -delete

# PDF 产物（素材 PDF 除外）
find . -type f -name '*.pdf' ! -path './_assets/*' -delete

rm -rf 09-figures-and-dragdrop/figures 03-multi-file-project/figures
rm -rf 08-shell-escape/_minted* 08-shell-escape/shell-escape-ok.txt
find . -type d -name '_minted*' -exec rm -rf {} + 2>/dev/null || true

# 被外部修改脚本改过的文件
git checkout -- 15-external-modification/watched.tex 2>/dev/null || true

# 重新生成需要特定字节形态的文件
python3 11-encoding-and-edge-cases/make-encoded.py >/dev/null
[ -f 10-large-document/big.tex ] || python3 10-large-document/generate.py >/dev/null

echo "testcases/ 已重置"
