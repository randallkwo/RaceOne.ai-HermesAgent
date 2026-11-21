#!/usr/bin/env bash
# 啟動 Hermes gateway（前景執行，Ctrl+C 結束）並檢查狀態
set -euo pipefail

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
PROFILE="${HERMES_PROFILE:-raceone-ai}"
ENV_FILE="$HERMES_HOME/profiles/$PROFILE/.env"

# 注意：hermes gateway 目前只讀預設 ~/.hermes，不會讀 HERMES_HOME。
# 因此若 HERMES_HOME 被覆寫（隔離測試用），本腳本會誤連正式 gateway，直接拒絕。
if [ "${HERMES_HOME:-$HOME/.hermes}" != "$HOME/.hermes" ]; then
  echo "拒絕啟動：HERMES_HOME 已被覆寫（$HERMES_HOME），gateway 只會讀預設 ~/.hermes。" >&2
  echo "請取消覆寫 HERMES_HOME 後再執行。" >&2
  exit 1
fi

if ! command -v hermes >/dev/null 2>&1; then
  echo "找不到 hermes，請先執行：bash scripts/setup.sh" >&2
  exit 1
fi
if [ ! -f "$ENV_FILE" ]; then
  echo "找不到 $ENV_FILE，請先執行 scripts/setup.sh" >&2
  exit 1
fi

# 檢查必填金鑰是否已改掉範例值（避免用占位字串啟動）
if grep -qE '^NVIDIA_API_KEY=(your_|$)' "$ENV_FILE"; then
  echo "NVIDIA_API_KEY 尚未填入，請編輯 $ENV_FILE" >&2
  exit 1
fi

echo "==> 狀態檢查"
hermes gateway status || true

echo "==> 前景啟動 gateway（Ctrl+C 結束）"
export HERMES_PROFILE="$PROFILE"
exec hermes gateway run
