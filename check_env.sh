#!/bin/sh
# check_env.sh  AIに制作を頼む前の、Mac の環境チェック（v2・2026-10-10）
# - この script がすることは、版の表示、フォルダの一覧、画面への表示だけです。
#   ファイルを作る命令と、通信をする命令は入れていません（コードの中を探して確かめました）。
# - 筆者の Mac で実行した前後に、~/.npm/_logs のファイル数が変わらないことを確かめました。
#   通信が出ないことを、通信の監視で測ったわけではありません。
# - 実行:  zsh check_env.sh   （bash check_env.sh でも動きます）
# - macOS 以外では「このスクリプトは Mac 用です」、Apple Silicon 以外の Mac では
#   「この手順の対象外です」と出して終わります。

if [ "$(uname -s)" != "Darwin" ]; then
  echo "このスクリプトは Mac 用です。"
  exit 0
fi

# 念のため: Python が .pyc を書かない、npm が更新確認をしない設定にして実行する
export PYTHONDONTWRITEBYTECODE=1
export NPM_CONFIG_UPDATE_NOTIFIER=false

# 出力に自分のホームのパスが出ないよう、~ に置き換える
mask() { sed "s|$HOME|~|g"; }

OK_COUNT=0
NG_COUNT=0
CHK_COUNT=0
NG_LIST=""
CHK_LIST=""

# report <名前> <OK|NG|CHK|REF> <詳細>
#   OK  = 入っている／問題なし
#   NG  = 足りない（件数に数える）
#   CHK = 要確認（足りないとは断定できない。件数は別に数える）
#   REF = 参考（使い方によっては要らない。件数に数えない）
report() {
  case "$2" in
    OK)
      OK_COUNT=$((OK_COUNT + 1))
      printf '[OK]       %-22s %s\n' "$1" "$3" | mask
      ;;
    NG)
      NG_COUNT=$((NG_COUNT + 1))
      NG_LIST="${NG_LIST}
  - $1"
      printf '[足りない] %-22s %s\n' "$1" "$3" | mask
      ;;
    CHK)
      CHK_COUNT=$((CHK_COUNT + 1))
      CHK_LIST="${CHK_LIST}
  - $1"
      printf '[要確認]   %-22s %s\n' "$1" "$3" | mask
      ;;
    *)
      printf '[参考]     %-22s %s\n' "$1" "$3" | mask
      ;;
  esac
}

# Xcode コマンドラインツールが無い Mac では、/usr/bin の git・python3・pip3 は
# 「インストールしますか」のダイアログを開くだけの代理(shim)です。実行すると
# ダイアログが開くので、先に有無を見て、無ければ実行しません。
CLT_OK=""
CLT_PATH=$(xcode-select -p 2>/dev/null)
if [ -n "$CLT_PATH" ] && [ -d "$CLT_PATH" ]; then
  CLT_OK=1
fi

# <コマンド名> が、CLT 無しの Mac の /usr/bin の代理なら 0（=実行してはいけない）
is_blocked_shim() {
  [ -z "$CLT_OK" ] || return 1
  p=$(command -v "$1" 2>/dev/null)
  [ "$p" = "/usr/bin/$1" ]
}

# 版が取れるコマンド用
check_cmd() { # <表示名> <コマンド> <版を出すコマンド（任意）>
  if command -v "$2" >/dev/null 2>&1; then
    if is_blocked_shim "$2"; then
      report "$1" NG "足りない（Xcode コマンドラインツール）"
      return
    fi
    if [ -n "$3" ]; then
      v=$(sh -c "$3" 2>/dev/null | head -n 1)
    else
      v=""
    fi
    if [ -n "$v" ]; then
      report "$1" OK "$v"
    else
      report "$1" OK "入っています（版は取れませんでした）"
    fi
  else
    report "$1" NG "見つかりません"
  fi
}

echo "== AI に制作を頼む前の環境チェック（Mac） =="
echo "版の表示と一覧の表示だけをします。通信とファイル作成の命令は入れていません。"
echo

# --- 本体の情報 ---------------------------------------------------------
ARCH=$(uname -m)
OSVER=$(sw_vers -productVersion 2>/dev/null)
OSMAJOR=${OSVER%%.*}
MEM_BYTES=$(sysctl -n hw.memsize 2>/dev/null)
MEM_GB=""
if [ -n "$MEM_BYTES" ]; then
  MEM_GB=$((MEM_BYTES / 1073741824))
fi

if [ "$ARCH" != "arm64" ]; then
  echo "[対象外]   CPU の種類: $ARCH"
  echo "この手順は Apple Silicon（M1 以降）の Mac 用です。この Mac は対象外なので、ここで終わります。"
  exit 0
fi
report "CPU の種類" OK "arm64 (Apple Silicon)"

# macOS の版。Claude Code は 13 以上、Codex は 12 以上、Playwright は 14 以上（公式）
case "$OSMAJOR" in
  ''|*[!0-9]*)
    report "macOS の版" CHK "${OSVER:-不明}（版を読み取れませんでした）"
    ;;
  *)
    if [ "$OSMAJOR" -ge 14 ]; then
      report "macOS の版" OK "$OSVER"
    elif [ "$OSMAJOR" -ge 13 ]; then
      report "macOS の版" CHK "$OSVER（Playwright の公式要件は macOS 14 以降です）"
    else
      report "macOS の版" NG "$OSVER（Claude Code の公式要件は macOS 13 以降、Playwright は 14 以降です）"
    fi
    ;;
esac

if [ -n "$MEM_GB" ] && [ "$MEM_GB" -ge 8 ]; then
  report "メモリ" OK "${MEM_GB} GB"
elif [ -n "$MEM_GB" ] && [ "$MEM_GB" -ge 4 ]; then
  report "メモリ" OK "${MEM_GB} GB（Claude Code と Codex の公式の最小は 4GB、Codex は 8GB を推奨しています）"
else
  report "メモリ" NG "${MEM_GB:-不明} GB（公式の最小は 4GB です）"
fi

# 空き容量（/）。20GB は目安です。足りない物には数えません
DF_LINE=$(df -h / 2>/dev/null | tail -n 1)
AVAIL_KB=$(df -k / 2>/dev/null | tail -n 1 | awk '{print $4}')
AVAIL_H=$(echo "$DF_LINE" | awk '{print $4}')
if [ -n "$AVAIL_KB" ] && [ "$AVAIL_KB" -ge 20971520 ] 2>/dev/null; then
  report "空き容量 (/)" OK "${AVAIL_H}"
else
  report "空き容量 (/)" CHK "${AVAIL_H:-不明}（20GB は目安です。会社では、空きとスワップを見て決めています）"
fi

# Rosetta（Apple Silicon のみ）。Intel 向けのアプリを動かすときだけ要ります
if /usr/bin/pgrep oahd >/dev/null 2>&1 || [ -f /Library/Apple/usr/share/rosetta/rosetta ]; then
  report "Rosetta" OK "入っています"
else
  report "Rosetta" REF "入っていません（Intel 向けのアプリを動かす時だけ要ります。今は入れなくて構いません）"
fi

# コマンドラインツール（git などが入っている）
if [ -n "$CLT_OK" ]; then
  report "Xcode コマンドラインツール" OK "入っています"
else
  report "Xcode コマンドラインツール" NG "入っていません（git・Python は、これを入れるまで確認しません）"
fi

# --- 道具 ----------------------------------------------------------------
check_cmd "Homebrew (brew)" brew "brew --version"
check_cmd "ffmpeg" ffmpeg "ffmpeg -version | awk '{print \$1, \$3}'"
check_cmd "git" git "git --version"

# Node.js：LTS の版の一覧で判定する（偶数・奇数では判定しない）。
# 一覧は https://nodejs.org/en/about/previous-releases を 2026-10-10 に確認した物。
# 新しい版が出ると変わるので、この一覧に無い版は「要確認」にする。
NODE_LTS_MAJORS=" 22 24 "
NODE_LTS_CHECKED="2026-10-10"
# 公式の日程では v26 が 2026-10-28 に LTS に入る予定。その後は " 22 24 26 " に直す。
if command -v node >/dev/null 2>&1; then
  NV=$(node -v 2>/dev/null)
  NMAJOR=$(echo "$NV" | sed 's/^v//' | cut -d. -f1)
  case "$NMAJOR" in
    ''|*[!0-9]*)
      report "Node.js" CHK "${NV:-版を読み取れませんでした}（LTS かどうか判定できません）"
      ;;
    *)
      case "$NODE_LTS_MAJORS" in
        *" $NMAJOR "*)
          report "Node.js" OK "$NV（LTS。一覧は ${NODE_LTS_CHECKED} に nodejs.org で確認した物）"
          ;;
        *)
          report "Node.js" CHK "$NV（${NODE_LTS_CHECKED} に確認した LTS の一覧は v22・v24 で、この版は入っていません。最新の一覧: https://nodejs.org/en/about/previous-releases ）"
          ;;
      esac
      ;;
  esac
else
  report "Node.js" NG "見つかりません"
fi
check_cmd "npm" npm "npm -v"

check_cmd "Python 3" python3 "python3 --version"

PIPCMD=""
for c in pip3 pip; do
  if command -v "$c" >/dev/null 2>&1; then
    PIPCMD="$c"
    break
  fi
done
if [ -z "$PIPCMD" ]; then
  report "pip" NG "見つかりません"
elif is_blocked_shim "$PIPCMD"; then
  report "pip" NG "足りない（Xcode コマンドラインツール）"
else
  PIPV=$("$PIPCMD" --version 2>/dev/null | awk '{print "pip " $2}' | head -n 1)
  report "pip" OK "${PIPV:-入っています（版は取れませんでした）}"
fi

# --- playwright と Chromium ---------------------------------------------
# npx は使いません（npm が動作ログを書くため）。
# Python 版は import できるか、Node 版は playwright コマンドがあるかで見ます。
PW_PY=""
if command -v python3 >/dev/null 2>&1 && ! is_blocked_shim python3; then
  if (cd / && python3 -B -c 'import playwright') >/dev/null 2>&1; then
    PW_PY=$(cd / && python3 -B -c 'import importlib.metadata as m; print(m.version("playwright"))' 2>/dev/null | head -n 1)
    PW_PY="${PW_PY:-版は取れませんでした}"
  fi
fi
PW_CMD=""
if command -v playwright >/dev/null 2>&1; then
  PW_CMD=1
fi
PW_TEXT=""
[ -n "$PW_PY" ] && PW_TEXT="Python 版あり（$PW_PY）"
[ -n "$PW_CMD" ] && PW_TEXT="${PW_TEXT:+$PW_TEXT / }playwright コマンドあり"
if [ -n "$PW_TEXT" ]; then
  report "playwright" OK "$PW_TEXT"
else
  report "playwright" NG "Python 版も playwright コマンドも見つかりません（フォルダごとに入れた Node 版は、ここでは見えません）"
fi

PW_DIR="${PLAYWRIGHT_BROWSERS_PATH:-$HOME/Library/Caches/ms-playwright}"
CHR=""
HEADLESS=""
if [ -d "$PW_DIR" ]; then
  CHR=$(ls "$PW_DIR" 2>/dev/null | grep '^chromium-[0-9]' | head -n 1)
  HEADLESS=$(ls "$PW_DIR" 2>/dev/null | grep '^chromium_headless_shell-' | head -n 1)
fi
if [ -n "$CHR" ]; then
  report "Chromium (playwright)" OK "$CHR"
elif [ -n "$HEADLESS" ]; then
  report "Chromium (playwright)" OK "$HEADLESS（画面なしで動かす用です。画面を出して動かす時は、通常の Chromium を入れます）"
else
  report "Chromium (playwright)" NG "見つかりません"
fi

# --- AI の道具（どちらか 1 つあれば足ります） -----------------------------
CLAUDE_OK=""; CODEX_OK=""
command -v claude >/dev/null 2>&1 && CLAUDE_OK=1
command -v codex  >/dev/null 2>&1 && CODEX_OK=1
if [ -n "$CLAUDE_OK" ] && [ -n "$CODEX_OK" ]; then
  report "Claude Code / Codex" OK "両方入っています（片方で足ります）"
elif [ -n "$CLAUDE_OK" ]; then
  report "Claude Code / Codex" OK "Claude Code が入っています"
elif [ -n "$CODEX_OK" ]; then
  report "Claude Code / Codex" OK "Codex が入っています"
else
  report "Claude Code / Codex" REF "コマンドとして見つかりません（アプリ版だけを使っている場合は、このままで構いません）"
fi

# --- まとめ --------------------------------------------------------------
echo
echo "== まとめ =="
echo "OK: ${OK_COUNT} 件 / 足りない: ${NG_COUNT} 件 / 要確認: ${CHK_COUNT} 件"
echo "（[参考] の行は、件数に入れていません）"
if [ "$NG_COUNT" -gt 0 ]; then
  echo "足りない物:${NG_LIST}"
fi
if [ "$CHK_COUNT" -gt 0 ]; then
  echo "要確認:${CHK_LIST}"
fi
if [ "$NG_COUNT" -gt 0 ] || [ "$CHK_COUNT" -gt 0 ]; then
  echo
  if [ "$NG_COUNT" -gt 0 ]; then
    echo "足りない物を入れるには、この出力をそのまま Claude Code か Codex に貼って"
    echo "「足りない物を入れて」と頼みます。"
  fi
  if [ "$CHK_COUNT" -gt 0 ]; then
    echo "要確認の行は、貼って「この行の意味と、直すべきかを教えて」と聞きます。"
  fi
else
  echo "足りない物も、要確認の行もありません。"
fi
exit 0
