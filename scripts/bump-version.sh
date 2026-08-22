#!/usr/bin/env bash
# 更新 Info.plist 中的应用版本和构建号。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INFO_PLIST="${INFO_PLIST:-$ROOT_DIR/Resources/Info.plist}"
CHANGELOG_FILE="${CHANGELOG_FILE:-$ROOT_DIR/CHANGELOG.md}"

usage() {
    cat <<'EOF'
用法：
  ./scripts/bump-version.sh <major|minor|patch|X.Y.Z> [选项]

选项：
  --build-number N       将 CFBundleVersion 设为 N
  --keep-build-number    保持当前构建号，不自动加 1
  --date YYYY-MM-DD      指定 changelog 的发布日期（默认为今天）
  --skip-changelog       仅更新 Info.plist，不归档 changelog
  --dry-run              仅显示结果，不修改文件
  -h, --help             显示帮助

示例：
  ./scripts/bump-version.sh patch
  ./scripts/bump-version.sh minor
  ./scripts/bump-version.sh 1.2.0 --build-number 42
EOF
}

if (( $# == 0 )); then
    usage >&2
    exit 1
fi

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    usage
    exit 0
fi

target="$1"
shift
requested_build_number=""
keep_build_number=false
release_date="$(date +%Y-%m-%d)"
update_changelog=true
dry_run=false

while (( $# > 0 )); do
    case "$1" in
        --build-number)
            if (( $# < 2 )); then
                echo "错误：--build-number 需要一个值" >&2
                exit 1
            fi
            requested_build_number="$2"
            shift 2
            ;;
        --keep-build-number)
            keep_build_number=true
            shift
            ;;
        --date)
            if (( $# < 2 )); then
                echo "错误：--date 需要一个值" >&2
                exit 1
            fi
            release_date="$2"
            shift 2
            ;;
        --skip-changelog)
            update_changelog=false
            shift
            ;;
        --dry-run)
            dry_run=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "错误：未知选项 $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ -n "$requested_build_number" && "$keep_build_number" == true ]]; then
    echo "错误：--build-number 与 --keep-build-number 不能同时使用" >&2
    exit 1
fi

if [[ ! "$release_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "错误：日期必须是 YYYY-MM-DD 格式，当前值为 $release_date" >&2
    exit 1
fi

if [[ ! -f "$INFO_PLIST" ]]; then
    echo "错误：找不到 Info.plist：$INFO_PLIST" >&2
    exit 1
fi

current_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
current_build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"

if [[ ! "$current_version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "错误：当前 CFBundleShortVersionString 不是 X.Y.Z 格式：$current_version" >&2
    exit 1
fi

major="${BASH_REMATCH[1]}"
minor="${BASH_REMATCH[2]}"
patch="${BASH_REMATCH[3]}"

case "$target" in
    major)
        new_version="$((major + 1)).0.0"
        ;;
    minor)
        new_version="$major.$((minor + 1)).0"
        ;;
    patch)
        new_version="$major.$minor.$((patch + 1))"
        ;;
    *)
        if [[ ! "$target" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "错误：版本必须是 major、minor、patch 或 X.Y.Z，当前值为 $target" >&2
            exit 1
        fi
        new_version="$target"
        ;;
esac

if [[ ! "$current_build_number" =~ ^[0-9]+$ ]]; then
    echo "错误：当前 CFBundleVersion 不是非负整数：$current_build_number" >&2
    exit 1
fi

if [[ -n "$requested_build_number" ]]; then
    new_build_number="$requested_build_number"
elif [[ "$keep_build_number" == true ]]; then
    new_build_number="$current_build_number"
else
    new_build_number="$((current_build_number + 1))"
fi

if [[ ! "$new_build_number" =~ ^[0-9]+$ ]]; then
    echo "错误：构建号必须是非负整数，当前值为 $new_build_number" >&2
    exit 1
fi

if [[ "$update_changelog" == true ]]; then
    if [[ ! -f "$CHANGELOG_FILE" ]]; then
        echo "错误：找不到 changelog：$CHANGELOG_FILE" >&2
        exit 1
    fi

    changelog_state="$(awk '
        $0 == "## [Unreleased]" {
            found = 1
            in_unreleased = 1
            next
        }
        in_unreleased && /^## \[/ {
            in_unreleased = 0
        }
        in_unreleased && $0 !~ /^[[:space:]]*$/ {
            has_content = 1
        }
        END {
            printf "%d:%d", found, has_content
        }
    ' "$CHANGELOG_FILE")"

    case "$changelog_state" in
        0:*)
            echo "错误：$CHANGELOG_FILE 缺少 ## [Unreleased] 段落" >&2
            exit 1
            ;;
        1:0)
            echo "错误：CHANGELOG.md 的 [Unreleased] 段落为空" >&2
            echo "请先记录变更，或使用 --skip-changelog" >&2
            exit 1
            ;;
    esac

    if grep -Fqx "## [$new_version]" "$CHANGELOG_FILE" \
        || grep -Fq "## [$new_version] - " "$CHANGELOG_FILE"; then
        echo "错误：CHANGELOG.md 已存在 $new_version 版本" >&2
        exit 1
    fi
fi

echo "版本：$current_version -> $new_version"
echo "构建号：$current_build_number -> $new_build_number"
if [[ "$update_changelog" == true ]]; then
    echo "Changelog：[Unreleased] -> [$new_version] - $release_date"
fi

if [[ "$dry_run" == true ]]; then
    echo "Dry run：未修改 $INFO_PLIST"
    exit 0
fi

plist_dir="$(cd "$(dirname "$INFO_PLIST")" && pwd)"
temporary_plist="$(mktemp "$plist_dir/.Info.plist.XXXXXX")"
temporary_changelog=""

cleanup() {
    [[ -z "$temporary_plist" ]] || rm -f "$temporary_plist"
    [[ -z "$temporary_changelog" ]] || rm -f "$temporary_changelog"
}
trap cleanup EXIT

cp -p "$INFO_PLIST" "$temporary_plist"

/usr/libexec/PlistBuddy \
    -c "Set :CFBundleShortVersionString $new_version" \
    -c "Set :CFBundleVersion $new_build_number" \
    "$temporary_plist"
plutil -lint "$temporary_plist" >/dev/null

if [[ "$update_changelog" == true ]]; then
    changelog_dir="$(cd "$(dirname "$CHANGELOG_FILE")" && pwd)"
    temporary_changelog="$(mktemp "$changelog_dir/.CHANGELOG.md.XXXXXX")"
    cp -p "$CHANGELOG_FILE" "$temporary_changelog"
    awk -v version="$new_version" -v release_date="$release_date" '
        !archived && $0 == "## [Unreleased]" {
            print
            print ""
            print "## [" version "] - " release_date
            archived = 1
            next
        }
        { print }
        END {
            if (!archived) {
                exit 1
            }
        }
    ' "$CHANGELOG_FILE" > "$temporary_changelog"
fi

mv "$temporary_plist" "$INFO_PLIST"
temporary_plist=""

if [[ "$update_changelog" == true ]]; then
    mv "$temporary_changelog" "$CHANGELOG_FILE"
    temporary_changelog=""
fi

trap - EXIT

echo "已更新：$INFO_PLIST"
if [[ "$update_changelog" == true ]]; then
    echo "已更新：$CHANGELOG_FILE"
fi
echo "发布标签：v$new_version"
