#!/usr/bin/env bash
# Hermes Agent 一鍵安裝（包裝官方安裝器）
# 用法：bash scripts/setup.sh
# 會：1) 依官方安裝器裝好 Hermes  2) 建立 $HERMES_HOME/.env（若不存在）
#     3) 把本 repo 的 config.yaml 範本套用到 profile（不覆蓋既有檔）
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
PROFILE_DIR="$HERMES_HOME/profiles/${HERMES_PROFILE:-raceone-ai}"

echo "==> 1/3 安裝 Hermes Agent（官方安裝器）"
if command -v hermes >/dev/null 2>&1; then
  echo "    已安裝：$(hermes --version 2>/dev/null | head -1)"
else
  curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh \
    | bash -s -- --skip-setup
fi

echo "==> 2/3 準備 .env（金鑰放這裡，權限 600）"
mkdir -p "$PROFILE_DIR"
if [ ! -f "$PROFILE_DIR/.env" ]; then
  cp "$REPO_DIR/.env.example" "$PROFILE_DIR/.env"
  chmod 600 "$PROFILE_DIR/.env"
  echo "    已建立 $PROFILE_DIR/.env ← 請填入 NVIDIA_API_KEY"
else
  echo "    已存在，未覆蓋：$PROFILE_DIR/.env"
fi

echo "==> 3/3 套用 config.yaml 範本（不覆蓋既有檔）"
if [ ! -f "$PROFILE_DIR/config.yaml" ]; then
  cp "$REPO_DIR/config.yaml" "$PROFILE_DIR/config.yaml"
  echo "    已建立 $PROFILE_DIR/config.yaml"
else
  echo "    已存在，未覆蓋：$PROFILE_DIR/config.yaml"
fi

echo "完成。下一步：編輯 $PROFILE_DIR/.env 後執行 bash scripts/start.sh"
