#!/usr/bin/env bash
# 输出 CHANGELOG.md 中指定版本的 Markdown 内容。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHANGELOG_FILE="${CHANGELOG_FILE:-$ROOT_DIR/CHANGELOG.md}"

if (( $# != 1 )) || [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "用法：./scripts/changelog-section.sh <X.Y.Z>" >&2
    exit 1
fi

version="$1"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "错误：版本必须是 X.Y.Z 格式，当前值为 $version" >&2
    exit 1
fi

if [[ ! -f "$CHANGELOG_FILE" ]]; then
    echo "错误：找不到 changelog：$CHANGELOG_FILE" >&2
    exit 1
fi

awk -v expected="## [$version]" '
    $0 == expected || index($0, expected " - ") == 1 {
        found = 1
        in_section = 1
        next
    }
    in_section && /^## \[/ {
        in_section = 0
    }
    in_section {
        if (!started && $0 ~ /^[[:space:]]*$/) {
            next
        }
        started = 1
        lines[++line_count] = $0
    }
    END {
        if (!found) {
            print "错误：changelog 中找不到版本 " expected > "/dev/stderr"
            exit 1
        }
        while (line_count > 0 && lines[line_count] ~ /^[[:space:]]*$/) {
            line_count--
        }
        if (line_count == 0) {
            print "错误：changelog 中的版本内容为空：" expected > "/dev/stderr"
            exit 1
        }
        for (line_number = 1; line_number <= line_count; line_number++) {
            print lines[line_number]
        }
    }
' "$CHANGELOG_FILE"
