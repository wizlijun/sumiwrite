#!/usr/bin/env bash
# 文档自检脚本。用法(从任意目录均可):
#   bash docs/check.sh                 运行全部检查
#   bash docs/check.sh check_links ... 只运行指定检查
# 失败时每条打印 "FAIL <检查名>: <原因>" 并以 1 退出;全部通过打印 OK。
# 环境变量 NOTEMD 指向 note.md 源仓库(默认 $HOME/git/note.md)。
# 兼容 macOS 自带 bash 3.2 与 BSD grep/sed/awk。

cd "$(dirname "$0")/.." || exit 2
NOTEMD="${NOTEMD:-$HOME/git/note.md}"
FAILED=0

fail() { # fail <检查名> <原因>
  echo "FAIL $1: $2"
  FAILED=1
}

# 列出仓库内的 *.md(跳过 .git 与 .superpowers)
list_md() {
  find . \( -name .git -o -name .superpowers \) -prune -o -type f -name '*.md' -print | sed 's|^\./||' | sort
}

# --- 任务 1 ------------------------------------------------------------

check_files() {
  local f
  for f in \
    LICENSE README.md AGENTS.md \
    docs/check.sh \
    docs/handoff/00-overview.md docs/handoff/01-inventory.md \
    docs/handoff/02-migration-plan.md docs/handoff/03-notemd-contract.md \
    docs/handoff/04-known-gaps.md \
    docs/spec/00-product.md docs/spec/01-pages-and-storage.md \
    docs/spec/02-markdown-and-line-time.md docs/spec/03-sync.md \
    docs/spec/04-editing-experience.md docs/spec/05-fonts.md docs/spec/MAPPING.md \
    docs/spec/platform/notemd-desktop.md docs/spec/platform/ios.md docs/spec/platform/later.md \
    docs/adr/0001-rust-core-yrs-yjs-v1.md \
    docs/adr/0002-single-ytext-line-time.md \
    docs/adr/0003-portable-files-and-sqlite-history.md \
    docs/adr/0004-cloudflare-sync-private-pairing.md \
    docs/adr/0005-native-text-controls.md \
    docs/adr/0006-plugin-backend-vs-host-session.md \
    docs/adr/0007-fonts-on-demand.md \
    docs/adr/0008-standalone-repo-desktop-stays-plugin.md \
    docs/adr/0009-page-store-vs-vault-projection.md \
    docs/adr/0010-ios-uikit-textkit2-uniffi.md \
    docs/adr/0011-ios-personal-use-identity-layer.md \
    docs/adr/0012-shared-session-module.md
  do
    if [ ! -e "$f" ]; then
      fail check_files "missing $f"
    elif [ ! -s "$f" ]; then
      fail check_files "empty $f"
    fi
  done
}

check_links() {
  local f dir link target
  while IFS= read -r f; do
    dir=$(dirname "$f")
    # 提取 ](...) 里的目标
    while IFS= read -r link; do
      target=${link#\](}
      target=${target%\)}
      target=${target%% *}          # 去掉 "title" 部分
      case "$target" in
        ''|http*|'#'*|mailto:*) continue ;;
      esac
      target=${target%%#*}          # 去掉锚点
      [ -z "$target" ] && continue
      if [ ! -e "$dir/$target" ]; then
        fail check_links "$f: broken link -> $target"
      fi
    done < <(grep -oE '\]\([^)]*\)' "$f")
  done < <(list_md)
}

# --- 任务 2 ------------------------------------------------------------

check_inventory() {
  local doc=docs/handoff/01-inventory.md s e
  if [ ! -f "$doc" ]; then fail check_inventory "missing $doc"; return; fi
  for s in 'write-core/' 'sumi-protocol/' 'write-sync-worker/' 'plugins-src/write/' \
           'tauri-plugin-native-editor/' 'src-tauri/src/sumi/' 'src/lib/sumi/' \
           'packaging/omarchy/fcitx5-sumi-candidates/' 'notemd-plugin-sdk/'; do
    grep -qF -- "$s" "$doc" || fail check_inventory "missing path: $s"
  done
  if [ ! -d "$NOTEMD/scripts/sumi" ]; then
    fail check_inventory "source dir not found: $NOTEMD/scripts/sumi"
    return
  fi
  while IFS= read -r e; do
    grep -qF -- "$e" "$doc" || fail check_inventory "scripts/sumi entry not mentioned: $e"
  done < <(ls "$NOTEMD/scripts/sumi")
}

# --- 任务 3 ------------------------------------------------------------

check_contract() {
  local doc=docs/handoff/03-notemd-contract.md cmd s modrs="$NOTEMD/src-tauri/src/sumi/mod.rs"
  if [ ! -f "$doc" ]; then fail check_contract "missing $doc"; return; fi
  if [ ! -f "$modrs" ]; then fail check_contract "source file not found: $modrs"; return; fi
  while IFS= read -r cmd; do
    cmd=${cmd%.}   # 句末标点带来的尾部点号
    [ -z "$cmd" ] && continue
    grep -qF -- "$cmd" "$doc" || fail check_contract "command not documented: $cmd"
  done < <(grep -ohE 'host\.sumi\.[A-Za-z0-9_.-]+' "$modrs" | sed 's/[.-]*$//' | sort -u)
  for s in 'host-contract v1' 'engines.notemd' 'Writing Page' '.writing.meta.json'; do
    grep -qF -- "$s" "$doc" || fail check_contract "missing: $s"
  done
}

# --- 任务 4 ------------------------------------------------------------

check_adr() {
  local n f base num want out
  n=$(find docs/adr -maxdepth 1 -type f -name '[0-9][0-9][0-9][0-9]-*.md' 2>/dev/null | wc -l | tr -d ' ')
  [ "$n" = "12" ] || fail check_adr "expected 12 NNNN-*.md files in docs/adr, found $n"
  while IFS= read -r f; do
    base=$(basename "$f")
    num=${base%%-*}
    if [ "$num" -le 7 ] 2>/dev/null; then want='补记'; else want='新'; fi
    # 二级标题按序出现;类型行位于第一个二级标题之前
    out=$(awk -v want="$want" '
      # 注意:BSD awk 的 == 用 strcoll,会把不同的汉字判为相等,故用 eq() 比较
      function eq(a, b) { return index(a, b) == 1 && length(a) == length(b) }
      BEGIN { split("背景 决定 放弃的方案 后果 来源", H, " "); idx = 1; typeok = 0; typeseen = 0; seen2 = 0; bad = "" }
      {
        line = $0; sub(/[ \t\r]+$/, "", line)
        if (line ~ /^## /) {
          seen2 = 1
          if (idx <= 5 && eq(line, "## " H[idx])) idx++
        }
        if (!seen2 && line ~ /^类型:/) {
          typeseen = 1
          if (eq(line, "类型:" want) || index(line, "类型:" want "(") == 1 || index(line, "类型:" want " ") == 1) typeok = 1
        }
      }
      END {
        if (idx <= 5) bad = bad "missing or out-of-order heading ## " H[idx] "; "
        if (!typeseen) bad = bad "no 类型: line before first ## heading; "
        else if (!typeok) bad = bad "类型 should be " want "; "
        if (bad != "") print bad
      }' "$f")
    [ -n "$out" ] && fail check_adr "$base: $out"
  done < <(find docs/adr -maxdepth 1 -type f -name '[0-9][0-9][0-9][0-9]-*.md' 2>/dev/null | sort)
}

# --- 任务 5 ------------------------------------------------------------

check_status() {
  local f out
  [ -d docs/spec ] || { fail check_status "missing docs/spec"; return; }
  while IFS= read -r f; do
    out=$(awk '
      function flush_pending() {
        if (pending != "") { print "line " pendline ": no status line after heading: " pending; pending = "" }
      }
      /^```/ { infence = !infence; next }
      infence { next }
      {
        line = $0; sub(/\r$/, "", line)
        if (pending != "") {
          if (line ~ /^[ \t]*$/) next
          if (line !~ /^状态:/) {
            print "line " NR ": first line after heading \"" pending "\" must start with 状态:"
          } else {
            ok = 0
            if (index(line, "[已交付:macOS+Linux]")) ok = 1
            else if (index(line, "[已交付:macOS]")) ok = 1
            else if (index(line, "[已交付:Linux]")) ok = 1
            else if (index(line, "[计划:iOS]")) ok = 1
            else if (index(line, "[未定]")) ok = 1
            if (!ok) print "line " NR ": status line has no valid label"
            if (index(line, "[已交付:") && !index(line, "https://github.com/wizlijun/note.md/blob/"))
              print "line " NR ": delivered status without evidence link"
          }
          pending = ""
        }
        if (line ~ /^### /) { pending = line; pendline = NR }
      }
      END { flush_pending() }' "$f")
    if [ -n "$out" ]; then
      while IFS= read -r msg; do fail check_status "$f: $msg"; done <<EOF2
$out
EOF2
    fi
  done < <(find docs/spec -type f -name '*.md' ! -name MAPPING.md | sort)
}

check_retired() {
  local w f
  [ -d docs/spec ] || { fail check_retired "missing docs/spec"; return; }
  while IFS= read -r f; do
    for w in 'inbox/write/' 'inbox/writes' '.write.md' 'Courier Prime' 'Special Elite' \
             '又又意宋' 'Sumi Typewriter' '玄霜打字机' 'Faitc5' 'Sumi Elite'; do
      if grep -qF -- "$w" "$f"; then
        fail check_retired "$f: retired term: $w"
      fi
    done
  done < <(
    find docs/spec -type f -name '*.md' ! -name MAPPING.md
    [ -f README.md ] && echo README.md
    [ -f AGENTS.md ] && echo AGENTS.md
  )
}

# --- 任务 7 ------------------------------------------------------------

check_ios() {
  local doc=docs/spec/platform/ios.md s m out
  if [ ! -f "$doc" ]; then fail check_ios "missing $doc"; return; fi
  for m in M0 M1 M2 M3 M4 M5; do
    grep -qE "(^|[^A-Za-z0-9])$m([^0-9]|$)" "$doc" || fail check_ios "missing milestone $m"
  done
  for s in 'iOS 17' 'UniFFI' 'TextKit 2' 'session'; do
    grep -qF -- "$s" "$doc" || fail check_ios "missing: $s"
  done
  grep -qF -- '[已交付' "$doc" && fail check_ios "must not contain [已交付"
  out=$(awk '
    /^```/ { infence = !infence }
    !infence && /^#{1,3} / { insec = ($0 ~ /^### 不做/) }
    index($0, "扫码") && !insec { print NR }' "$doc")
  if [ -n "$out" ]; then
    fail check_ios "扫码 outside '### 不做' section at line(s): $(echo $out)"
  fi
}

# --- 任务 8 ------------------------------------------------------------

check_mapping() {
  local map=docs/spec/MAPPING.md spec="$NOTEMD/docs/superpowers/specs" f base h
  if [ ! -f "$map" ]; then fail check_mapping "missing $map"; return; fi
  if [ ! -d "$spec" ]; then fail check_mapping "source dir not found: $spec"; return; fi
  while IFS= read -r base; do
    [ -z "$base" ] && continue
    f="$spec/$base"
    if [ ! -f "$f" ]; then fail check_mapping "old doc not found in source: $base"; continue; fi
    grep -qF -- "$base" "$map" || fail check_mapping "old doc not mapped: $base"
  done < <(
    {
      echo 2026-11-07-immersive-write-design.md
      ls "$spec" | grep -i sumi | grep -vi sumiwrite
      echo 2026-11-08-plugin-payload-extraction.md
      echo 2026-11-11-writing-plugin-groups.md
      echo 2026-11-10-omarchy-plugin-shortcuts.md
      echo 2026-11-11-release-input-method-companion.md
      echo 2026-11-12-fcitx5-name-correction.md
      echo 2026-11-11-omarchy-amd64-ime-release.md
    } | sort -u
  )
  f="$spec/2026-11-07-immersive-write-design.md"
  if [ -f "$f" ]; then
    while IFS= read -r h; do
      h=${h#\#\# }
      h=$(printf '%s' "$h" | sed 's/[[:space:]]*$//')
      [ -z "$h" ] && continue
      grep -qF -- "$h" "$map" || fail check_mapping "main spec heading not mapped: $h"
    done < <(grep '^## ' "$f")
  fi
}

# --- 任务 9 ------------------------------------------------------------

check_plan() {
  local plan=docs/handoff/02-migration-plan.md gaps=docs/handoff/04-known-gaps.md n k out
  if [ ! -f "$plan" ]; then
    fail check_plan "missing $plan"
  else
    for n in 1 2 3 4 5; do
      grep -qE "^## 第 $n 期" "$plan" || fail check_plan "missing heading: ## 第 $n 期"
    done
    for n in 1 2 3; do
      for k in 前置条件 步骤 验证 回退; do
        out=$(awk -v n="$n" -v k="$k" '
          /^```/ { infence = !infence }
          !infence && /^## / { insec = ($0 ~ ("^## 第 " n " 期")) ; next }
          insec && !infence && $0 ~ /^#{3,6} / {
            t = $0; sub(/^#+ +/, "", t)
            if (index(t, k) == 1) found = 1
          }
          END { if (found) print "y" }' "$plan")
        [ "$out" = "y" ] || fail check_plan "第 $n 期 missing subheading: $k"
      done
    done
  fi
  if [ ! -f "$gaps" ]; then
    fail check_plan "missing $gaps"
  else
    for n in 1 2 3 4 5 6 7 8 9 10; do
      grep -qE "(^|[^A-Za-z0-9])P$n([^0-9]|$)" "$gaps" || fail check_plan "known-gaps missing P$n"
    done
  fi
}

# --- 调度 --------------------------------------------------------------

ALL_CHECKS="check_files check_links check_inventory check_contract check_adr check_status check_retired check_ios check_mapping check_plan"

if [ $# -eq 0 ]; then
  set -- $ALL_CHECKS
fi
for c in "$@"; do
  case " $ALL_CHECKS " in
    *" $c "*) "$c" ;;
    *) fail "$c" "unknown check (available: $ALL_CHECKS)" ;;
  esac
done

if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
echo OK
