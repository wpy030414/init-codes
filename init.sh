#!/usr/bin/env bash
#
# init.sh — 初始化 macOS 的 ~/Codes 目录
#
# 与 init.ps1（Windows）对应：创建目录、设置语义化图标、在 Finder 中打开。
# 仅依赖 macOS 自带组件（bash / osascript / AppKit），无需 Homebrew。
#
set -euo pipefail

TARGET="${HOME}/Codes"
ICON_SOURCE=""
RESET=false
OPEN_AFTER=true
PIN=true

usage() {
  cat <<'EOF'
init.sh — 初始化 macOS 的 ~/Codes 目录

用法:
  ./init.sh [选项]

选项:
  --dir <路径>    目标目录（默认: ~/Codes）
  --icon <文件>   使用自定义图标（.icns / .png / .tiff 等）
                  默认生成「系统文件夹 + </> 代码符号」图标
  --reset         移除自定义图标，恢复系统默认文件夹图标
  --no-pin        不加入 Finder「个人收藏」（默认会加入）
  --no-open       完成后不自动打开 Finder
  -h, --help      显示本帮助

说明:
  - 仅支持 macOS 11+；更早版本会自动退回到系统内置的「开发者文件夹」图标。
  - 加入「个人收藏」需要 Xcode 命令行工具里的 clang（现场编译一个小辅助程序）；
    没有 clang 时会跳过这一步，不影响目录和图标。
  - 目录的 Finder 显示名称即文件夹名；macOS 不支持像 Windows desktop.ini 那样
    为普通文件夹单独指定显示名。
EOF
}

info() { printf '%s\n' "$*"; }
warn() { printf '提示：%s\n' "$*" >&2; }
die()  { printf '错误：%s\n' "$*" >&2; exit 1; }

expand_tilde() {
  case "$1" in
    '~')    printf '%s\n' "$HOME" ;;
    '~/'*)  printf '%s\n' "${HOME}/${1#"~/"}" ;;
    *)      printf '%s\n' "$1" ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)
      [[ $# -ge 2 ]] || die "--dir 需要一个路径参数"
      TARGET="$2"; shift 2 ;;
    --dir=*)
      TARGET="${1#*=}"; shift ;;
    --icon)
      [[ $# -ge 2 ]] || die "--icon 需要一个文件路径"
      ICON_SOURCE="$2"; shift 2 ;;
    --icon=*)
      ICON_SOURCE="${1#*=}"; shift ;;
    --reset)
      RESET=true; shift ;;
    --no-pin)
      PIN=false; shift ;;
    --no-open)
      OPEN_AFTER=false; shift ;;
    -h|--help)
      usage; exit 0 ;;
    --)
      shift; break ;;
    *)
      die "未知参数：$1（用 --help 查看用法）" ;;
  esac
done
[[ $# -eq 0 ]] || die "多余的参数：$*（用 --help 查看用法）"

# ── 平台检查 ────────────────────────────────────────────────────────────
if [[ "$(uname -s)" != "Darwin" ]]; then
  die "本脚本仅支持 macOS。Windows 请使用 init.ps1。"
fi
command -v osascript >/dev/null 2>&1 || die "找不到 osascript，无法设置图标。"

if [[ -n "$ICON_SOURCE" && "$RESET" == true ]]; then
  die "--reset 与 --icon 不能同时使用。"
fi

# ── 准备目录 ────────────────────────────────────────────────────────────
TARGET="$(expand_tilde "$TARGET")"
[[ -n "$TARGET" ]] || die "--dir 不能为空。"
[[ "$TARGET" == "/" ]] || TARGET="${TARGET%/}"

# 先校验图标参数，再去创建目录：参数有误时不应留下任何副作用
if [[ -n "$ICON_SOURCE" ]]; then
  ICON_SOURCE="$(expand_tilde "$ICON_SOURCE")"
  [[ -f "$ICON_SOURCE" ]] || die "图标文件不存在：$ICON_SOURCE"
  ICON_SOURCE="$(cd "$(dirname "$ICON_SOURCE")" && pwd -P)/$(basename "$ICON_SOURCE")"
fi

if [[ -e "$TARGET" && ! -d "$TARGET" ]]; then
  die "已存在同名文件而不是目录：$TARGET"
fi

if [[ ! -d "$TARGET" ]]; then
  mkdir -p "$TARGET"
  info "已创建目录：$TARGET"
else
  info "目录已存在：$TARGET"
fi

# 转成绝对路径，避免相对路径在 JXA 进程中解析位置不一致
TARGET="$(cd "$TARGET" && pwd -P)"

# ── 图标 ────────────────────────────────────────────────────────────────
# macOS 的自定义文件夹图标由目录内隐藏文件 Icon\r 承载：其资源分支存图标，
# 目录的 com.apple.FinderInfo 标记 kHasCustomIcon。这里通过 NSWorkspace 的
# 官方 API 写入（等于 Finder 里「显示简介 → 粘贴图标」），不手工拼资源分支。
#
# 默认图标的语义选择：
#   取系统当前版本的通用文件夹图标，叠上 SF Symbol
#   chevron.left.forwardslash.chevron.right —— 也就是代码符号 </>，
#   这是系统里与「代码」语义最直接对应的图形；比 DeveloperFolderIcon
#   （锤子，偏「开发工具」）和 Terminal 图标（偏「终端」）都更贴题。
#   若系统没有 SF Symbols（macOS 11 以下），自动退回 DeveloperFolderIcon.icns。

STATUS_FILE="$(mktemp "${TMPDIR:-/tmp}/init-codes-status.XXXXXX")"
cleanup() { rm -f "$STATUS_FILE"; }
trap cleanup EXIT

if [[ "$RESET" == true ]]; then
  ICON_MODE="reset"
elif [[ -n "$ICON_SOURCE" ]]; then
  ICON_MODE="custom"
else
  ICON_MODE="default"
fi

run_jxa() {
  ICON_MODE="$ICON_MODE" \
  ICON_TARGET="$TARGET" \
  ICON_SOURCE="$ICON_SOURCE" \
  ICON_FALLBACK="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/DeveloperFolderIcon.icns" \
  ICON_STATUS_FILE="$STATUS_FILE" \
  osascript -l JavaScript - <<'JXA'
ObjC.import('AppKit');
ObjC.import('Foundation');

var SIZE = 1024;

function env(name) {
  var v = $.NSProcessInfo.processInfo.environment.objectForKey(name);
  return v && !v.isNil() ? ObjC.unwrap(v) : '';
}

function fail(message) { throw new Error(message); }

function writeStatus(text) {
  var ok = $.NSString.stringWithString(text)
    .writeToFileAtomicallyEncodingError(env('ICON_STATUS_FILE'), true, $.NSUTF8StringEncoding, $());
  if (!ok) fail('无法写入状态文件');
}

var mode     = env('ICON_MODE');
var target   = env('ICON_TARGET');
var source   = env('ICON_SOURCE');
var fallback = env('ICON_FALLBACK');
var ws       = $.NSWorkspace.sharedWorkspace;

// 把任意图片等比缩放、居中放进 1024×1024 的透明画布
function normalizeImage(img) {
  var w = ObjC.unwrap(img.size.width);
  var h = ObjC.unwrap(img.size.height);
  if (!w || !h) fail('图标尺寸无效');

  var out = $.NSImage.alloc.initWithSize($.NSMakeSize(SIZE, SIZE));
  out.lockFocus;
  var scale = Math.min(SIZE / w, SIZE / h);
  var dw = w * scale;
  var dh = h * scale;
  img.drawInRectFromRectOperationFraction(
    $.NSMakeRect((SIZE - dw) / 2, (SIZE - dh) / 2, dw, dh),
    $.NSZeroRect, $.NSCompositingOperationSourceOver, 1.0);
  out.unlockFocus;
  return out;
}

// 系统默认文件夹图标 + 深蓝色 </> 代码符号
function composeCodeFolder() {
  var symbol;
  try {
    symbol = $.NSImage.imageWithSystemSymbolNameAccessibilityDescription(
      'chevron.left.forwardslash.chevron.right', $());
  } catch (e) {
    return null;  // macOS 10.x 没有 SF Symbols 接口
  }
  if (!symbol || symbol.isNil()) return null;

  // 尺寸交给 NSImageSymbolConfiguration，保证放大后仍然清晰
  try {
    symbol = symbol.imageWithSymbolConfiguration(
      $.NSImageSymbolConfiguration.configurationWithPointSizeWeight(480, 0.3));
  } catch (e) { /* 保持原始尺寸 */ }

  var sw = ObjC.unwrap(symbol.size.width);
  var sh = ObjC.unwrap(symbol.size.height);
  if (!sw || !sh) return null;

  // 系统文件夹里的图形是「比底色深一档的同色系」，不是纯白。
  // 这里用 SourceAtop 把符号涂成同样的深蓝色，避免自定义图标在 Finder 里显得突兀。
  var tinted = $.NSImage.alloc.initWithSize($.NSMakeSize(sw, sh));
  tinted.lockFocus;
  symbol.drawInRectFromRectOperationFraction(
    $.NSMakeRect(0, 0, sw, sh),
    $.NSZeroRect, $.NSCompositingOperationSourceOver, 1.0);
  $.NSColor.colorWithSRGBRedGreenBlueAlpha(83 / 255, 167 / 255, 205 / 255, 1.0).set;
  $.NSRectFillUsingOperation($.NSMakeRect(0, 0, sw, sh), $.NSCompositingOperationSourceAtop);
  tinted.unlockFocus;
  symbol = tinted;

  // 取「当前系统」的通用文件夹图标：对空目录调用 iconForFile
  var fm = $.NSFileManager.defaultManager;
  var tmp = ObjC.unwrap($.NSTemporaryDirectory())
          + 'init-codes-icon-' + ObjC.unwrap($.NSProcessInfo.processInfo.processIdentifier);
  fm.createDirectoryAtPathWithIntermediateDirectoriesAttributesError(tmp, true, $(), $());
  var folder = ws.iconForFile(tmp);

  var out = $.NSImage.alloc.initWithSize($.NSMakeSize(SIZE, SIZE));
  out.lockFocus;
  folder.drawInRectFromRectOperationFraction(
    $.NSMakeRect(0, 0, SIZE, SIZE),
    $.NSZeroRect, $.NSCompositingOperationSourceOver, 1.0);

  var w = SIZE * 0.42;
  var h = w * sh / sw;
  // 文件夹图标的「正面面板」中心比画布中心低约 6.5%：
  // 按画布居中会让符号显得偏上，这里向下补偿到面板的视觉中心。
  var y = (SIZE - h) / 2 - SIZE * 0.065;
  symbol.drawInRectFromRectOperationFraction(
    $.NSMakeRect((SIZE - w) / 2, y, w, h),
    $.NSZeroRect, $.NSCompositingOperationSourceOver, 1.0);
  out.unlockFocus;

  fm.removeItemAtPathError(tmp, $());
  return out;
}

var status;
if (mode === 'reset') {
  // 传 nil 图片 = 移除自定义图标
  if (!ws.setIconForFileOptions($(), target, 0)) fail('移除自定义图标失败');
  status = 'reset';
} else {
  var image;
  if (mode === 'custom') {
    image = $.NSImage.alloc.initWithContentsOfFile(source);
    if (!image || image.isNil()) fail('无法读取图标文件：' + source);
    image = normalizeImage(image);
    status = 'custom';
  } else {
    image = composeCodeFolder();
    status = image ? 'default' : 'fallback';
    if (!image) {
      image = $.NSImage.alloc.initWithContentsOfFile(fallback);
      if (!image || image.isNil()) fail('无法生成默认图标');
    }
  }

  if (!ws.setIconForFileOptions(image, target, 0)) fail('设置图标失败（目录可能不可写）');
  if (!$.NSFileManager.defaultManager.fileExistsAtPath(target + '/Icon\r')) {
    fail('图标文件未生成');
  }
}
writeStatus(status);
JXA
}

info "正在设置图标……"
if ! run_jxa; then
  die "设置图标失败。可尝试用 --icon 指定一个 .icns 文件。"
fi

case "$(cat "$STATUS_FILE" 2>/dev/null || true)" in
  default)  info "已设置图标：系统文件夹 + </> 代码符号" ;;
  fallback) warn "当前系统不支持代码符号，已改用内置的「开发者文件夹」图标。"
            info "已设置图标：开发者文件夹（系统内置）" ;;
  custom)   info "已设置图标：$ICON_SOURCE" ;;
  reset)    info "已移除自定义图标，恢复系统默认图标。" ;;
  *)        warn "图标已写入，但未收到状态回执。" ;;
esac

# ── 加入 Finder「个人收藏」 ──────────────────────────────────────────────
# Finder 侧边栏没有官方命令行接口：LSSharedFileList 自 10.11 起被标记为废弃，
# 但至今仍在工作，mysides 等第三方工具走的也是它。这里现场编译一个极小的 C
# 辅助程序，先查重再插入；没有 clang 就跳过，不影响目录和图标。
pin_to_favorites() {
  local tmpdir src bin result

  if ! command -v clang >/dev/null 2>&1; then
    warn "未找到 clang（需要 Xcode 命令行工具），跳过加入 Finder「个人收藏」。"
    return 1
  fi

  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/init-codes-sidebar.XXXXXX")"
  src="$tmpdir/sidebar.c"
  bin="$tmpdir/sidebar"

  cat > "$src" <<'C'
#include <CoreServices/CoreServices.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc < 2) return 2;

    LSSharedFileListRef list = LSSharedFileListCreate(NULL, kLSSharedFileListFavoriteItems, NULL);
    if (!list) return 2;

    OptionBits seed = 0;
    CFArrayRef snapshot = LSSharedFileListCopySnapshot(list, &seed);
    if (!snapshot) return 2;

    int found = 0;
    for (CFIndex i = 0; i < CFArrayGetCount(snapshot); i++) {
        LSSharedFileListItemRef item = (LSSharedFileListItemRef)CFArrayGetValueAtIndex(snapshot, i);
        CFErrorRef error = NULL;
        CFURLRef url = LSSharedFileListItemCopyResolvedURL(item, 0, &error);
        if (!url) continue;
        UInt8 buffer[PATH_MAX];
        Boolean ok = CFURLGetFileSystemRepresentation(url, true, buffer, sizeof(buffer));
        CFRelease(url);
        if (ok && strcmp((char *)buffer, argv[1]) == 0) { found = 1; break; }
    }
    CFRelease(snapshot);

    if (found) { printf("already\n"); return 0; }

    CFStringRef path = CFStringCreateWithCString(NULL, argv[1], kCFStringEncodingUTF8);
    if (!path) return 2;
    CFURLRef url = CFURLCreateWithFileSystemPath(NULL, path, kCFURLPOSIXPathStyle, true);
    CFRelease(path);
    if (!url) return 2;

    LSSharedFileListItemRef inserted =
        LSSharedFileListInsertItemURL(list, kLSSharedFileListItemLast, NULL, NULL, url, NULL, NULL);
    CFRelease(url);

    if (!inserted) { printf("failed\n"); return 1; }
    printf("pinned\n");
    return 0;
}
C

  if ! clang -O1 -Wno-deprecated-declarations -o "$bin" "$src" -framework CoreServices >/dev/null 2>&1; then
    rm -rf "$tmpdir"
    warn "个人收藏辅助程序编译失败，跳过。"
    return 1
  fi

  result="$("$bin" "$TARGET" 2>/dev/null || true)"
  rm -rf "$tmpdir"

  case "$result" in
    pinned)  info "已加入 Finder「个人收藏」：$TARGET" ;;
    already) info "已在 Finder「个人收藏」中：$TARGET" ;;
    *)       warn "加入 Finder「个人收藏」失败，可手动拖入侧边栏。"
             return 1 ;;
  esac
}

if [[ "$PIN" == true ]]; then
  pin_to_favorites || true
fi

# 触一下目录时间戳，促使 Finder 重绘图标（资源分支更新通常已即时生效）
touch "$TARGET" 2>/dev/null || true

# ── 收尾 ────────────────────────────────────────────────────────────────
if [[ "$OPEN_AFTER" == true ]]; then
  if open "$TARGET" 2>/dev/null; then
    info "已在 Finder 中打开：$TARGET"
  else
    warn "无法打开 Finder（可能处于无图形界面环境），目录已就绪：$TARGET"
  fi
else
  info "完成：$TARGET"
fi

info "若图标没有立即变化，在 Finder 中按 ⌘R 或重新打开窗口即可。"
