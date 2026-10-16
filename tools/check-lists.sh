#!/usr/bin/env bash
# check-lists.sh —— 校验 packages.d/*.list 的格式
# 规则：非注释行每行一个包；"a|b" 备选写法；包名只允许小写字母/数字/+/-/./~
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

fail=0
for f in packages.d/*.list; do
  lineno=0
  while IFS= read -r line; do
    lineno=$((lineno + 1))
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    # 去掉行内注释和空白
    line="${line%%#*}"
    line="${line//[[:space:]]/}"
    [[ -z "$line" ]] && continue
    # 校验每个备选包名
    IFS='|' read -ra parts <<< "$line"
    for p in "${parts[@]}"; do
      if ! [[ "$p" =~ ^[a-z0-9][a-z0-9+._~-]*$ ]]; then
        echo "✗ $f:$lineno 非法包名: $p"; fail=1
      fi
    done
  done < "$f"
done

if [[ $fail -eq 0 ]]; then
  total=$(cat packages.d/*.list | grep -cvE '^\s*(#|$)')
  echo "✓ 全部清单格式正确，共 $total 个包条目"
fi
exit $fail
