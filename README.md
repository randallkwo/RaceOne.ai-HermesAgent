# Hermes Agent 一鍵安裝（RaceOne）

把 [Hermes Agent](https://hermes-agent.nousresearch.com/docs) 裝好並接上 NVIDIA 模型。
**你只需要填入 NVIDIA API Key。**

## 需求

- Linux 或 macOS，能連上網際網路
- 一把 NVIDIA API Key（[build.nvidia.com](https://build.nvidia.com) 申請）
- （選用）OpenRouter API Key、Telegram Bot Token

## 三步驟

```bash
git clone https://github.com/randallkwo/RaceOne.ai-HermesAgent.git
cd RaceOne.ai-HermesAgent
bash scripts/setup.sh
```

1. `setup.sh` 會呼叫 Hermes **官方安裝器**安裝 Hermes（已裝過就跳過），並建立設定檔。
2. 編輯金鑰檔（權限自動設為 600）：

   ```bash
   nano ~/.hermes/profiles/raceone-ai/.env
   ```

   把 `NVIDIA_API_KEY=` 後面填上你的 key。
3. 啟動：

   ```bash
   bash scripts/start.sh
   ```

   `start.sh` 會先檢查金鑰是否已填，未填會拒絕啟動。

## 檔案說明

| 檔案 | 用途 |
|------|------|
| `scripts/setup.sh` | 安裝 Hermes、建立 `.env` 與 `config.yaml`（不覆蓋既有檔） |
| `scripts/start.sh` | 檢查金鑰後，前景啟動 Hermes gateway |
| `config.yaml` | 最小設定範本：NVIDIA 為主要模型，金鑰從 `.env` 讀取 |
| `.env.example` | 金鑰欄位範本（只有欄位名，沒有值） |

## 安全

- 金鑰只放在 `~/.hermes/profiles/raceone-ai/.env`，**不在 repo 裡**。
- `.gitignore` 排除 `.env`、`*.key`、`*.pem` 等。
- `config.yaml` 不含任何金鑰或個人 ID。

## 已知限制

- `start.sh` 會在前景執行 gateway；要常駐請用 `hermes gateway install`（見官方文件）。
- `start.sh` 只支援預設 `~/.hermes`。`hermes gateway` 目前不讀 `HERMES_HOME`，覆寫時腳本會拒絕執行，避免誤連其他實例。
- `setup.sh` 在隔離環境（臨時 `HERMES_HOME`）驗證過；**完整的 Telegram 與模型對話尚未在乾淨機器端到端驗證**。
- 本 repo 不含 Telegram、MCP 等進階設定；需要的話請參考官方文件。

## 授權

本專案以 [MIT License](LICENSE) 授權。注意：這個授權只涵蓋本 repo 的腳本與範本；Hermes Agent 本身與 NVIDIA、OpenRouter 等服務各有其自己的條款。
