#!/usr/bin/env bash
# 内嵌输入法(ios.md §3.6)的模拟器端到端检查:在专用模拟器上打开实体键盘、装上并启动应用,用 RimeKit 的
# simkey 发真实的 HID 按键,每一步之后截图到 build/sim-rime/<场景>/(build/ 被 git 忽略)。点按(候选、
# 状态字和它的菜单项、‹ ›)由 UI 测试 SumiWriteUITests/TapServer 代点。只做测试工具,不进 Verification;截图由人
# (或 agent)逐张看,对照下面写的预期判定。
#
# 用法:bash apps/ios/scripts/sim-rime.sh [--no-build] [场景...]
#   场景:builtin middle repeat focus shift english switch toggle tap(默认全部,按此顺序)
#   环境变量:SIM_RIME_DEVICE 专用模拟器的名字(默认 sumi-rime-e2e,没有就建一台 iPad Pro 11-inch (M5));
#            RIME 指 RimeKit 仓库(默认与本仓库同级的 rime-kit)。
# 每个场景先按 ⌘N 新建空白页,在空白页里做。
#
# 全程:候选行在光标的下一行;有组字或候选时整行带主题底色,右端最后一个是状态字(中 / 英 / 系,比正文小、
# 颜色淡,紧挨 › 或最后一个候选);空闲时(下文「空闲」)只在右端剩状态字那一小块底色,下一行其余的字露出来。
# 任何截图(toggle 的 t03 除外)都不出现系统的候选条。
#
# builtin  00 ⌘N:空白页,空闲:右端只有一小块「中」。
#          b01 n i h a o:光标处是带下划线的组字(拼音,如「ni hao」),候选行第一个是「1 你好」且带下划线。
#          b02 Space:「你好」上屏,组字与候选消失,回到空闲,光标在「你好」之后。
# middle   m01 1 2 3 4 5 6 ⏎ 7 8 9 0 ↑:第一行「123456」,光标在其中(约在 4 之后);空闲,第二行「7890」露出,
#              右端「中」那一小块在第二行的高度。
#          m02 n i h a o:组字插在第一行光标处,同一行里它后面的数字往后挪(后文回流);候选行整行不透明,盖住第二行。
#          m03 Space:第一行是「1234你好56」之类(你好插在光标处)。
#          m04 ↓:光标到第二行,第二行「7890」露出且原样,第一行仍是 m03 的样子。
# repeat   r01 二十个数字:一行数字(已进入聚焦打字,当前行在屏幕中部)。
#          r02 按住 k 一秒:组字里有多个 k(连发)。
#          r03 Esc:组字清掉,数字不变;仍在聚焦,这一行不跳回页首。
#          r04 按住 ⌫ 一秒:末尾的多个数字被删(连发),不止一个。
# focus    f01 ⌘V:粘进 30 段会自动换行的长文字(脚本先用 simctl pbcopy 放进模拟器剪贴板),光标在文末。
#          f02 ⌘↑、↓ 30 次、← ← ←、n i h a o:光标挪到长页中部某一行的中间再组字;已进入聚焦打字(光标行在
#              屏幕中部,上下渐隐);候选行紧贴在光标行的下一行。(要光标在长页中间、上下都有大段文字;光标在文末时排版估计值恰好准,修复前也看不出跳动。)
#          f03 Space:「你好」上屏;候选行仍紧贴光标行的下一行,与 f02 同一高度,不上移盖住光标行或它上面的字
#              (真机反馈 2026-11-20 的「上屏后候选行上移」)。
#          f04 n i h a o Space:再上屏一次,同 f03。
# shift    s01 单按左 Shift:状态字「中」变「英」。
#          s02 a b c:「abc」直接上屏,没有组字、没有候选,仍空闲。
#          s03 单按左 Shift:「英」变回「中」。
#          s04 n i h a o Space:「abc你好」。
#          s05 单按右 Shift:仍是「中」(雾凇 default.yaml 的 Shift_R: noop)。
# english  e01 点状态字:弹出系统菜单「中文」「英文」「系统输入法」,「中文」打勾。
#          e02 点「英文」:菜单收起,状态字变「英」。
#          e03 a b c:「abc」直接上屏,没有组字、没有候选,仍空闲。
#          e04 点状态字、点「中文」:状态字变回「中」。
#          e05 n i h a o Space:「abc你好」。
# switch   w01 n i h a o:组字中(同 b01)。
#          w02 ⌘]:末页按 › 新建一页:新的空白页,没有组字,空闲(只有「中」一小块),没有「请先完成输入」。
#          w03 ⌘[:回到上一页,原文「nihao」已上屏(不是标记文字,没有下划线,也没有候选)。
# toggle   t01 n i h a o:组字中。
#          t02 点状态字、点「系统输入法」:组字清掉(不上屏,正文为空),状态字变「系」;仍在聚焦,光标行不跳回页首。
#          t03 n i h a o:按键交给系统输入法(本机系统输入源第一个是简体拼音,所以可能出现系统的组字或候选条,
#              也可能是英文字母直接上屏);候选行里没有内置的候选,右端仍是「系」那一小块。
#          t04 Space、点状态字、点「中文」:系统那边结束;状态字变回「中」。
#          t05 n i h a o:又是内置的组字与候选(同 b01)。
#          t06 Space:「你好」上屏。
# tap      p01 n i h a o:组字中。
#          p02 点 ›(下一页候选):候选行换成后面的候选,组字不变。
#          p03 点 ‹(上一页候选):回到第一页,又看到「你好」。
#          p04 点「你好」:「你好」上屏,组字与候选消失。
set -uo pipefail
IOS="$(cd "$(dirname "$0")/.." && pwd)"
RIME="${RIME:-$IOS/../../../rime-kit}"
OUT="$IOS/build/sim-rime"
BIN="$OUT/bin"
DD="$IOS/build/dd-sim-rime"
SYNC="$OUT/sync"
NAME="${SIM_RIME_DEVICE:-sumi-rime-e2e}"

build=1
if [ "${1:-}" = --no-build ]; then build=0; shift; fi
SC="${*:-builtin middle repeat focus shift english switch toggle tap}"

mkdir -p "$BIN"
for t in simkey hwkb; do
  src="$RIME/tools/sim/$t.m"
  [ -f "$src" ] || { echo "缺 $src:见 apps/ios/README.md" >&2; exit 1; }
  [ -x "$BIN/$t" ] && [ "$BIN/$t" -nt "$src" ] || clang -fobjc-arc -framework Foundation -o "$BIN/$t" "$src" || exit 1
done

# 专用模拟器:按名字找,没有就建,不动别的模拟器。
U=$(xcrun simctl list devices -j | python3 -I -c '
import json, sys
name = sys.argv[1]
for rt, devs in json.load(sys.stdin)["devices"].items():
    for d in devs:
        if d["name"] == name and d.get("isAvailable", True):
            print(d["udid"]); sys.exit()
' "$NAME")
if [ -z "$U" ]; then
  RT=$(xcrun simctl list runtimes -j | python3 -I -c '
import json, sys
rs = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS" and r["isAvailable"]]
print(rs[-1]["identifier"])')
  U=$(xcrun simctl create "$NAME" "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-11-inch-M5-12GB" "$RT") || exit 1
  echo "建了模拟器 $NAME ($U)"
fi
DEST="platform=iOS Simulator,id=$U"

if [ $build = 1 ]; then
  bash "$RIME/scripts/fetch.sh" || exit 1
  bash "$IOS/scripts/build-core.sh" || exit 1
  (cd "$IOS" && xcodegen generate) || exit 1
  xcodebuild build-for-testing -project "$IOS/SumiWrite.xcodeproj" -scheme SumiWriteUI -destination "$DEST" \
    -derivedDataPath "$DD" -quiet || exit 1
fi
APP="$DD/Build/Products/Debug-iphonesimulator/SumiWrite.app"
[ -d "$APP" ] || { echo "缺 $APP:去掉 --no-build 重跑" >&2; exit 1; }
B=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")

# 系统输入源第一个设成简体拼音(按键若漏给系统,会看到系统的候选条),设过就不再重启。
want='zh_Hans-Pinyin@sw=Pinyin-Simplified;hw=US'
xcrun simctl boot "$U" 2>/dev/null
xcrun simctl bootstatus "$U" >/dev/null
if ! xcrun simctl spawn "$U" defaults read -g AppleKeyboards 2>/dev/null | grep -q "$want"; then
  xcrun simctl spawn "$U" defaults write -g AppleKeyboards -array "$want" "en_US@sw=QWERTY;hw=Automatic"
  xcrun simctl shutdown "$U"
  xcrun simctl boot "$U"
  xcrun simctl bootstatus "$U" >/dev/null
  sleep 10
fi
open -a Simulator --args -CurrentDeviceUDID "$U" 2>/dev/null

xcrun simctl terminate "$U" "$B" 2>/dev/null
xcrun simctl install "$U" "$APP" || exit 1
# 模拟器会在一些事件之后丢掉实体键盘:每 0.3 秒重新打开。
(while :; do "$BIN/hwkb" "$U" on >/dev/null 2>&1; sleep 0.3; done) &
LOOP=$!
SERVER=
cleanup() {
  kill $LOOP 2>/dev/null
  if [ -n "$SERVER" ]; then
    printf 'quit\n' > "$SYNC/cmd.tmp" && mv "$SYNC/cmd.tmp" "$SYNC/cmd"
    for _ in $(seq 1 100); do kill -0 "$SERVER" 2>/dev/null || break; sleep 0.2; done
    kill "$SERVER" 2>/dev/null
  fi
}
trap cleanup EXIT
sleep 1
xcrun simctl launch "$U" "$B" >/dev/null || exit 1

# 首次部署要一会儿(候选行显示「部署中…」):等编出的词库表出现、目录大小连续 3 秒不变。
mkdir -p "$OUT"
sleep 3
xcrun simctl io "$U" screenshot "$OUT/deploy.png" >/dev/null 2>&1
data=$(xcrun simctl get_app_container "$U" "$B" data)
build_dir="$data/Library/Application Support/Rime/build"
last= same=0
for _ in $(seq 1 600); do
  if ls "$build_dir"/*.prism.bin "$build_dir"/*.table.bin >/dev/null 2>&1; then
    size=$(du -sk "$build_dir" | cut -f1)
    if [ "$size" = "$last" ]; then same=$((same + 1)); else same=0; last=$size; fi
    [ $same -ge 3 ] && break
  fi
  sleep 1
done
[ $same -ge 3 ] || { echo "部署没有结束:$build_dir" >&2; exit 1; }
sleep 2
echo "部署完成"

key() { "$BIN/simkey" "$U" "$@"; }
shot() { sleep 0.8; xcrun simctl io "$U" screenshot "$DIR/$1.png" >/dev/null 2>&1; echo "  $1"; }
# step <截图名> [按键...]
step() { local n=$1; shift; [ $# -gt 0 ] && key "$@"; shot "$n"; }

serve() {
  [ -n "$SERVER" ] && return 0
  rm -rf "$SYNC"; mkdir -p "$SYNC"
  TEST_RUNNER_SIM_RIME_SYNC="$SYNC" xcodebuild test-without-building -project "$IOS/SumiWrite.xcodeproj" \
    -scheme SumiWriteUI -destination "$DEST" -derivedDataPath "$DD" \
    -only-testing:SumiWriteUITests/TapServer/testServe > "$OUT/tapserver.log" 2>&1 &
  SERVER=$!
  for _ in $(seq 1 600); do [ -f "$SYNC/ready" ] && break; kill -0 $SERVER 2>/dev/null || break; sleep 0.5; done
  [ -f "$SYNC/ready" ] || { echo "TapServer 没起来,见 $OUT/tapserver.log" >&2; exit 1; }
  sleep 2
}
# tap <截图名> <无障碍标签>
tap() {
  local n=$1 label=$2
  rm -f "$SYNC/done"
  printf 'tap %s\n' "$label" > "$SYNC/cmd.tmp" && mv "$SYNC/cmd.tmp" "$SYNC/cmd"
  for _ in $(seq 1 400); do [ -f "$SYNC/done" ] && break; sleep 0.1; done
  local r; r=$(cat "$SYNC/done" 2>/dev/null || echo timeout)
  [ "$r" = ok ] || echo "  点「${label}」:${r}" >&2
  [ -n "$n" ] && shot "$n"
}
# choose <截图名> <菜单项>:点状态字,等菜单弹出,点菜单项。
choose() {
  tap "" 切换输入法
  sleep 0.5
  tap "$1" "$2"
}

for s in $SC; do
  DIR="$OUT/$s"; rm -rf "$DIR"; mkdir -p "$DIR"
  echo "$s"
  case $s in
  english | toggle | tap) serve ;;
  esac
  step 00-new C+n
  case $s in
  builtin)
    step b01-nihao n i h a o
    step b02-space SPACE
    ;;
  middle)
    step m01-two-lines 1 2 3 4 5 6 RET 7 8 9 0 UP
    step m02-nihao n i h a o
    step m03-space SPACE
    step m04-down DOWN
    ;;
  repeat)
    step r01-digits 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0
    step r02-hold-k HOLD:k:1000
    step r03-esc ESC
    step r04-hold-bs HOLD:BS:1000
    ;;
  focus)
    para="这是一段比较长的文字，用来让它在屏幕上自动换行，看看上屏之后候选行会不会往上跳、盖住正文。"
    para="$para$para$para"
    for _ in $(seq 1 30); do printf '%s\n' "$para"; done | xcrun simctl pbcopy "$U"
    step f01-paste C+v
    step f02-nihao C+UP $(printf 'DOWN %.0s' $(seq 1 30)) LEFT LEFT LEFT n i h a o
    step f03-space SPACE
    step f04-again n i h a o SPACE
    ;;
  shift)
    step s01-shift SHIFT
    step s02-abc a b c
    step s03-shift SHIFT
    step s04-nihao n i h a o SPACE
    step s05-right-shift RSHIFT
    ;;
  english)
    tap e01-menu 切换输入法
    tap e02-english 英文
    step e03-abc a b c
    choose e04-chinese 中文
    step e05-nihao n i h a o SPACE
    ;;
  switch)
    step w01-nihao n i h a o
    step w02-next C+]
    step w03-prev C+[
    ;;
  toggle)
    step t01-nihao n i h a o
    choose t02-to-system 系统输入法
    step t03-system-nihao n i h a o
    key SPACE
    choose t04-to-builtin 中文
    step t05-nihao n i h a o
    step t06-space SPACE
    ;;
  tap)
    step p01-nihao n i h a o
    tap p02-next-page 下一页候选
    tap p03-prev-page 上一页候选
    tap p04-tap-nihao 你好
    ;;
  *) echo "未知场景 $s" >&2 ;;
  esac
done
echo "截图在 $OUT"
