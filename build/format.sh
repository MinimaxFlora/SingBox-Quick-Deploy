#!/usr/bin/env bash
# 统一代码格式（shfmt）。CI 使用 shfmt -d 校验。
set -Eeuo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

SHFMT=${SHFMT:-}
if [[ -z ${SHFMT} ]]; then
  if command -v shfmt > /dev/null 2>&1; then
    SHFMT=$(command -v shfmt)
  elif [[ -x /tmp/shfmt ]]; then
    SHFMT='/tmp/shfmt'
  else
    printf 'shfmt not found: https://github.com/mvdan/sh/releases\n' >&2
    exit 1
  fi
fi

"${SHFMT}" -w -i 2 -ci -sr src build install.sh tests
printf 'formatted with %s\n' "$("${SHFMT}" --version)"
