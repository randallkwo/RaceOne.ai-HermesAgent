# Hermes Agent 安裝與設定說明書（整合版）v2.1

**版本：v2.1（2026-11-20 修訂，取代 v2.0）**
**適用對象：非資訊背景的同仁；能開啟終端機並貼上指令即可**
**產品：Hermes Agent（Nous Research 開源 AI 助理框架）**
**實測範圍：Docker 乾淨環境（Ubuntu 24.04）安裝；1 vCPU / 1 GB + 2 GB swap 雲端主機安裝與 NVIDIA 對話；本機 hermes 指令輸出**
**官方參考：hermes-agent.nousresearch.com/docs；build.nvidia.com 官方 FAQ**

> **注意：本文件不含任何金鑰或 Token；所有示範值皆以 [範例] 標示；價格以供應商官網為準**

---

## v2.1 修訂重點

| 項目 | v2.0 | v2.1 |
|------|------|------|
| 緊急停止 | 寫 `hermes pause` / `hermes resume` | **已移除**：這兩個子命令不存在。改用 `systemctl stop` 停止閘道（見 5.6） |
| 閘道服務 | 未提醒服務衝突 | **新增 5.5 節警告**：只能保留一個服務（system 或 user），不可同時存在 |
| 閘道子命令 | 只列常用子命令 | **補上** `migrate-legacy`、`enroll`，並說明 `--system` 旗標 |
| 版本指令 | 未說明 | **明確標註**指令以 `hermes --help` 為準 |

---

## 0. 總覽與名詞

Hermes 是跑在您自己電腦或雲端主機上的 AI 助理程式。它負責理解需求、呼叫工具、記住偏好；實際生成文字的是外部模型（NVIDIA 免費 API、Claude 或 ChatGPT）。Telegram 是您與助理對話的介面。

| 名詞 | 白話說明 |
|------|----------|
| Hermes | 助理程式本身，安裝在電腦或雲端主機上 |
| 模型 | AI 大腦，例如 NVIDIA Nemotron、Claude、ChatGPT；需要帳號或 API 金鑰 |
| API 金鑰 | 像密碼的字串，用來證明您有權呼叫模型；可能計費，NVIDIA 免費層則為速率限制 |
| OAuth 登入 | 以瀏覽器登入帳號授權，不需貼金鑰（ChatGPT 可用此方式） |
| Telegram Bot | 在 @BotFather 建立的機器人帳號，使用一組 Token |
| 閘道 | 讓 Hermes 持續在背景運作、接收 Telegram 訊息的服務 |
| config.yaml | 一般設定（例如預設模型），放在 `~/.hermes/`，不放密碼 |
| .env 檔 | 只放金鑰與 Token 等機密，放在 `~/.hermes/.env` |
| Swap | 硬碟上的虛擬記憶體，記憶體不足時的緩衝；1 GB 主機安裝時需要 |

> **設計原則：機密只放 .env；一般設定用 `hermes config set` 修改；不要把任何金鑰或 Token 貼到聊天室、LINE、Telegram 或截圖中。**

---

## 1. 前置準備

| 項目 | 需求 | 備註 |
|------|------|------|
| 主機 | Linux（建議 Ubuntu 22.04／24.04 LTS）、macOS，或 Windows（需 WSL2） | 雲端主機見第 4 節；睡眠時 Telegram 無法回應 |
| 記憶體 | 2 GB RAM（建議）；或 1 GB RAM + 2 GB swap（最低成本） | 實測：1 GB 無 swap 會在建置網頁介面時卡死，見 2.3 節 |
| 系統套件 | curl、git、ca-certificates | 安裝程式需要 git，缺少會失敗（Docker 測試已確認） |
| 網路 | 可連上網際網路 | 需存取模型服務與 Telegram |
| 模型帳號 | NVIDIA 免費金鑰（建議先用）；或 Claude／ChatGPT | 見第 3 節 |
| Telegram | 已可正常使用 Telegram；您的數字 ID | 數字 ID 用於允許名單，見 5.2 節 |

**Linux 安裝系統套件的指令（Ubuntu／Debian）：**
```bash
apt-get update && apt-get install -y curl git ca-certificates
```

---

## 2. 安裝 Hermes

### 2.1 Linux 或 macOS

在終端機貼上下列指令，安裝程式會自動安裝 Python、Node 與相依套件（約 2 分鐘）：

```bash
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
```

安裝完成後開新的終端機視窗，確認版本：

```bash
hermes --version
```

### 2.2 Windows（WSL2）

1. 以系統管理員身分開啟 PowerShell，執行 `wsl --install`，依提示重新開機。
2. 開啟 Ubuntu（WSL）終端機，之後的所有步驟都在 WSL 中執行。
3. 在 WSL 中執行 2.1 節的指令。WSL 不支援背景服務時，請改用前景執行（見 5.5 節）。

### 2.3 1 GB 主機：先設定 2 GB swap（必做）

1 GB 記憶體的機器若沒有 swap，安裝時會在建置網頁介面（web UI）階段耗盡記憶體而卡死。以 root 執行：

```bash
fallocate -l 2G /swapfile && chmod 600 /swapfile
mkswap /swapfile && swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
free -m
```

> **實測結果**：加上 2 GB swap 後，安裝約 2 分 20 秒完成；安裝後使用約 355 MB RAM，swap 約 35 MB。2 GB 以上的主機可略過此步。

### 2.4 第一次設定與健康檢查

```bash
hermes setup
hermes doctor
```

> **doctor 全部通過才進行下一步；若有錯誤，請對照第 8 節。**

### 2.5 重要路徑

| 路徑 | 用途 |
|------|------|
| `~/.hermes/config.yaml` | 一般設定（不放機密） |
| `~/.hermes/.env` | API 金鑰與 Telegram Token（機密）；可用 `hermes config env-path` 確認 |
| `~/.hermes/logs/` | 閘道與錯誤紀錄，排錯時查看 |
| `~/.hermes/state.db` | 對話紀錄與記憶資料 |

---

## 3. 接上模型

### 3.1 先確認費用方式

- **NVIDIA 免費 API**：官方 FAQ 說明可免費用於原型開發，大多數模型約 40 RPM（每分鐘請求數），不按 token 計費；超過速率限制會失敗或變慢。網路上常見的「1,000 credits」說法已過時。
- **Claude、ChatGPT**：網頁訂閱與 API 計費是兩套系統；使用 API 金鑰會依用量計費，請在後台設定月額度上限。
- **以帳號登入（OAuth）**：是否可用於第三方程式，請以各家最新服務條款為準，本文不作保證。

### 3.2 方案 A（建議，成本最低）：NVIDIA 免費 API

1. 到 `build.nvidia.com` 註冊 NVIDIA Developer 帳號（免費，不需信用卡）。
2. 前往 `build.nvidia.com/settings/api-keys`，點選產生金鑰；金鑰以 `nvapi-` 開頭，只顯示一次，請立即存好。
3. 在伺服器執行 `nano ~/.hermes/.env`，新增一行（等號前後不要空格，不需引號）：
   ```bash
   NVIDIA_API_KEY=[請填入您自己的 nvapi- 金鑰]
   ```
4. 測試連線（模型 ID 請先到 `build.nvidia.com/models` 確認）：
   ```bash
   hermes chat --provider nvidia --model nvidia/nemotron-3.5-super-vl-120b-a12b -q "請只回覆：連線測試成功"
   ```

> **實測**：此模型在 1 GB + 2 GB swap 的雲端主機與 Docker 乾淨環境中都成功回覆（約 30–40 秒，含啟動時間）。`NVIDIA_BASE_URL` 不需設定，預設為 `https://integrate.api.nvidia.com/v1`。

> **v2.1 註**：2026-11-20 以 NVIDIA 模型列表核對，上述兩個模型 ID（`nvidia/nemotron-3.5-super-vl-120b-a12b`、`nvidia/nemotron-3-ultra-550b-a55b`）皆存在。模型會增減，使用前請再確認。

### 3.3 方案 B：Claude（Anthropic，API 金鑰）

1. 在 Anthropic Console 建立 API 金鑰，並設定付款方式與用量上限。
2. 在 `~/.hermes/.env` 新增一行，然後執行 `hermes model` 選擇 anthropic 與模型：
   ```bash
   ANTHROPIC_API_KEY=[範例：請填入您自己的金鑰]
   ```

### 3.4 方案 C：ChatGPT（OpenAI）

- **選項一：以 ChatGPT 帳號授權（OAuth，不需貼金鑰）**
  ```bash
  hermes auth add openai-codex
  ```
  依指示在瀏覽器登入並授權，完成後以 `hermes model` 選擇 `openai-codex` 的模型。

- **選項二：以 OpenAI API 金鑰連線**：在後台建立金鑰，執行 `hermes model` 選擇 `custom`，依畫面填入端點與金鑰；金鑰仍只寫入 `.env`。

### 3.5 設定預設模型

選定後，以 `hermes model` 互動選單設定預設值。模型設定請用指令，不要手改 `config.yaml`：

```bash
hermes model
```

> 若出現 401（認證錯誤）或額度不足，請檢查金鑰是否正確、帳戶是否有餘額或額度；NVIDIA 若出現 429，代表超過速率限制，請稍後再試。

---

## 4. 低成本雲端主機

### 4.1 規格與實測

| 項目 | 建議 | 理由／實測 |
|------|------|------------|
| RAM | 2 GB（建議）；或 1 GB + 2 GB swap | 1 GB 無 swap 會卡死；加 swap 後安裝成功，安裝後約 355 MB RAM |
| CPU | 1 vCPU 以上 | 單人使用足夠；多個閘道或大型索引才需升級 |
| 磁碟 | 25 GB 以上 | Ubuntu 基礎系統已佔約 1.9 GB；需另預留對話紀錄、日誌與更新空間 |
| 作業系統 | Ubuntu 22.04／24.04 LTS | 安裝指令在 Linux 上測試最完整 |
| 地區 | 離使用者近的機房 | 降低 Telegram 回覆延遲 |

### 4.2 價格（請以官網當下價格為準）

- **DigitalOcean**：1 GB 入門方案約 $6/月（配 2 GB swap 即可運作）；2 GB 方案約 $12/月，免 swap 設定。
- **Hetzner**：入門方案通常更便宜，但需確認可用地區與帳號審核條件。[待確認] 本文未查核實際價格。
- **選擇原則**：先確認 RAM（2 GB，或 1 GB 加 swap），再比較月費與流量額度。

### 4.3 建立主機（以 DigitalOcean 為例）

1. 登入後點選 Create → Droplets；映像檔選 Ubuntu LTS；方案依 4.2 節選擇。
2. 加入 SSH 金鑰（比密碼安全），建立後記下公開 IP。
3. 以 `ssh root@<主機IP>` 登入（請替換為您的主機 IP）。
4. 1 GB 方案：先依 2.3 節設定 swap，再進行安裝。

### 4.4 安裝與設定（依序執行）

```bash
apt-get update && apt-get install -y curl git ca-certificates
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
hermes setup
hermes doctor
```

在 `hermes setup` 中選擇 NVIDIA（或其他方案），金鑰依 3.2 節寫入 `.env`；doctor 全部通過後再進行下一步。

---

## 5. 串接 Telegram

### 5.1 用 @BotFather 建立機器人

1. 在 Telegram 搜尋 @BotFather（官方機器人管理工具）。
2. 傳送 `/newbot`；輸入顯示名稱（可任意取名，例如：Hermes 助理）。
3. 輸入使用者名稱，必須唯一且以 `bot` 結尾（例如：`my_hermes_bot`）。
4. BotFather 會回覆一組 API Token，格式類似 `123456789:ABC…`（以下為範例，非真實值）。

> **Token 等同於 bot 的密碼。外洩時請立刻傳送 `/revoke` 給 BotFather 撤銷，並重新產生。**

### 5.2 取得您的數字 ID（允許名單用）

Telegram 的允許名單使用「數字 ID」，不是使用者名稱。可向第三方機器人（例如 @userinfobot）查詢；查詢機器人屬於外部服務，請自行評估風險。

### 5.3 設定 Token 與允許名單

在 `~/.hermes/.env` 新增以下兩行（數值為範例）：

```bash
TELEGRAM_BOT_TOKEN=[範例：BotFather 給您的 Token]
TELEGRAM_ALLOWED_USERS=[範例：您的數字 ID，多人以逗號分隔]
```

> **TELEGRAM_ALLOWED_USERS 非常重要**：沒有設定時，任何找到 bot 的人都可能使用，並消耗您的模型額度。

### 5.4 平台設定（二選一）

- **方法 A**：執行 `hermes gateway setup`，依畫面設定 Telegram。
- **方法 B**：若安裝了儀表板，可在「Messaging → Telegram」按「Create with QR」，掃碼後自動寫入 `.env` 並重啟閘道。

### 5.5 閘道服務：只能保留一個（v2.1 新增）

> ⚠️ **閘道可以安裝為背景服務**（Linux 用 systemd，macOS 用 launchd）。**同一個閘道只能由一個服務管理。** 若同時存在兩份服務（例如系統級與使用者級各一份），兩者會互相判定對方為「已在執行」而不斷重啟，形成重啟風暴：
> - 日誌出現 `Gateway already running (PID …)`，每數秒一次；
> - 服務的重啟次數持續增加（數萬次）；
> - Telegram 收發不穩定。

**規則：**

1. **Linux 請使用系統級服務（開機自動啟動）**，安裝時加上 `--system`：
   ```bash
   hermes gateway install --system
   ```
2. 不要在不加 `--system` 的情況下重複安裝；預設安裝會建立使用者級服務，與系統級並存時就會發生衝突。
3. `hermes gateway` 的子命令（`start`、`stop`、`restart`、`status`）預設作用於使用者級服務。若您使用系統級服務，請以 `systemctl` 操作，或確認指令的目標服務。
4. 若發現兩份服務並存，請先確認哪一份正持有閘道程序（看 PID），保留該份，停用另一份。操作前請先保留一條可回復的路徑，例如在獨立的 SSH 終端執行，避免中斷自己的對話。

**檢查服務狀態（以系統級為例）：**
```bash
systemctl status hermes-gateway-<profile>.service
journalctl -u hermes-gateway-<profile>.service -n 50 --no-pager
```

### 5.6 啟動與停止閘道

建議先用前景模式測試（可看即時日誌，Ctrl+C 停止）：
```bash
hermes gateway run
```

確認沒問題後，安裝為背景服務（Linux 請加 `--system`，見 5.5 節）：
```bash
hermes gateway install --system
hermes gateway start
hermes gateway status
```

**停止閘道（v2.1 修正：取代 v2.0 中不存在的 `hermes pause`）：**
```bash
hermes gateway stop
```

若閘道以系統級服務執行，停止時請改用：
```bash
systemctl stop hermes-gateway-<profile>.service
```

重新啟動：`hermes gateway restart`（系統級服務請用 `systemctl restart hermes-gateway-<profile>.service`）。

> **注意**：Hermes 不允許閘道從自己的程序內停止或重啟自己（會把正在執行的指令一起終止）。請從獨立的 SSH 終端執行這些指令。

### 5.7 測試對話

在 Telegram 中找到您的 bot，傳送「你好，請自我介紹」。若 bot 回覆，代表串接成功。傳送 `/new` 可開始新的對話；對話紀錄保存在 `state.db`。

---

## 6. 安全與日常維運

| 項目 | 做法 | 原因 |
|------|------|------|
| 金鑰與 Token | 只放 `.env`；不貼聊天室、截圖、LINE | 外洩會被盜用或產生費用 |
| 允許名單 | **一定設定** `TELEGRAM_ALLOWED_USERS` | 防止陌生人使用您的 bot |
| 額度上限 | 在 NVIDIA／Anthropic／OpenAI 後台設定用量或月額度 | 防止異常用量造成大額帳單 |
| 定期檢查 | `hermes doctor`；查看 `~/.hermes/logs/` | 及早發現設定或連線問題 |
| 服務數量 | 確認只有一份閘道服務（見 5.5 節） | 避免重啟風暴 |
| 緊急停止 | `hermes gateway stop`（系統級服務用 `systemctl stop`） | 異常時快速止血。v2.0 的 `hermes pause`/`resume` 不存在，已移除 |
| 設定變更 | 用 `hermes config set KEY VALUE` | 避免手改格式錯誤導致服務中斷 |
| 資料庫維護 | `state.db` 過大時可開啟 `sessions.auto_prune`；先停閘道再執行 `hermes sessions optimize-storage`，並先備份 | 實測：1.62 GB 縮減為 542 MB |
| 備份 | 定期備份 `~/.hermes/`（含 `.env`，加密保存） | 避免主機故障後遺失記憶與設定 |
| 測試主機 | 測完即刪，避免持續計費 | 雲端主機按時計費 |

> **注意**：備份檔含金鑰，請加密後再存放，不要放在公開的雲端資料夾。

---

## 7. 指令速查表

| 目的 | 指令 |
|------|------|
| 安裝（Linux／macOS） | `curl -fsSL https://hermes-agent.nousresearch.com/install.sh \| bash` |
| 查看版本 | `hermes --version` |
| 設定精靈 | `hermes setup` |
| 健康檢查 | `hermes doctor` |
| 選擇模型與供應商 | `hermes model` |
| NVIDIA 連線測試 | `hermes chat --provider nvidia --model <模型ID> -q "…"` |
| 帳號授權（ChatGPT） | `hermes auth add openai-codex` |
| 單次測試提問 | `hermes chat -q "…"` |
| 查看 .env 路徑 | `hermes config env-path` |
| 修改一般設定 | `hermes config set 鍵 值` |
| Telegram 設定精靈 | `hermes gateway setup` |
| 前景執行閘道 | `hermes gateway run` |
| 安裝背景服務（Linux 系統級） | `hermes gateway install --system` |
| 啟動／狀態 | `hermes gateway start` / `hermes gateway status` |
| 停止閘道 | `hermes gateway stop`（v2.1 修正） |
| 列出服務 | `hermes gateway list`（v2.1 新增） |
| 遷移舊版服務 | `hermes gateway migrate-legacy`（v2.1 新增；只處理舊版 `hermes.service`，不處理 profile 服務） |
| 閘道與中繼連接 | `hermes gateway enroll`（v2.1 新增；寫入中繼認證至 `.env`） |

> **若您的版本指令與本表不同，請以 `hermes --help` 與 `hermes <指令> --help` 為準。**

---

## 8. 疑難排解

| 現象 | 可能原因 | 處理方式 |
|------|----------|----------|
| 安裝卡住或主機無回應 | 1 GB 記憶體不足，未設定 swap | 依 2.3 節加 2 GB swap 後重新安裝 |
| 安裝失敗，提到 git | 系統未安裝 git | `apt-get install -y git` 後重跑安裝指令 |
| `hermes` 指令找不到 | 安裝後未重新開啟終端機 | 開新視窗；或 `source ~/.bashrc`；確認 `~/.local/bin` 在 PATH |
| `doctor` 出現錯誤 | 相依套件或設定缺漏 | 依 `doctor` 輸出逐項修正，再重跑 `hermes doctor` |
| 模型回報 401 | 金鑰錯誤或過期 | 重新產生金鑰，更新 `.env` 後重啟閘道 |
| NVIDIA 回報 429 | 超過免費層速率限制 | 稍後重試；降低併發；必要時改用付費方案 |
| 模型回報額度不足 | API 帳戶無餘額或達上限 | 至後台確認餘額與用量上限 |
| Telegram 不回應 | 閘道未執行、Token 有誤、ID 不在允許名單 | `hermes gateway status`；核對 Token 與數字 ID；看 logs |
| 日誌出現 `Gateway already running` 且不斷重啟 | 同時存在兩份閘道服務 | 只保留一份服務，停用另一份（見 5.5） |
| bot 對任何人都回應 | 未設定允許名單 | 立即設定 `TELEGRAM_ALLOWED_USERS` 並重啟閘道 |
| WSL 無法背景執行 | WSL 不支援背景服務 | 改用 `hermes gateway run` 前景執行 |
| 電腦睡眠後沒反應 | 主機休眠 | 關閉睡眠或改用常開的伺服器 |
| Token 疑似外洩 | Token 被他人取得 | BotFather 傳 `/revoke`，重新產生並更新 `.env` |

---

## 9. 成本與風險

| 項目 | 費用來源 | 注意事項 |
|------|----------|----------|
| 雲端主機 | VPS 月費（1 GB 約 $6；2 GB 約 $12，以官網為準） | 測試用主機測完即刪 |
| 模型（NVIDIA 免費層） | $0，在速率限制內 | 超過速率限制會失敗或變慢；官方定位為原型開發，正式服務需改付費或自架 |
| 模型（Claude／ChatGPT API） | 依 token 計費 | 需設定月額度上限 |
| 網域、備份 | 可選 | 非必要；備份請加密保存，因含金鑰 |

### 風險提醒

- NVIDIA 免費層用於正式服務可能違反條款，請依 NVIDIA 最新條款使用。
- 速率限制會影響多人同時使用的體驗，建議先以單人測試。
- 主機與金鑰都應開啟兩步驟驗證或防火牆限制，降低被盜用的風險。

---

## 10. 完成檢查表

| # | 檢查項目 | 完成 |
|---|----------|------|
| 1 | NVIDIA 金鑰已存於 `~/.hermes/.env`（未貼到任何聊天） | ☐ |
| 2 | `hermes --version` 顯示版本 | ☐ |
| 3 | `hermes doctor` 全部通過 | ☐ |
| 4 | `hermes chat --provider nvidia` 測試成功（或已設定其他模型並測試） | ☐ |
| 5 | 主機記憶體符合要求：2 GB，或 1 GB 且已設定 2 GB swap（`free -m` 可見） | ☐ |
| 6 | BotFather 已建立 bot，Token 只存在 `.env` | ☐ |
| 7 | `TELEGRAM_ALLOWED_USERS` 已設定為自己的數字 ID | ☐ |
| 8 | 只有一份閘道服務在執行（見 5.5 節）；`hermes gateway status` 顯示執行中，Telegram 傳訊息可正常回覆 | ☐ |
| 9 | 已設定模型用量上限，並已排定 `state.db` 與 `.env` 的備份 | ☐ |
| 10 | 已記錄主機與模型的實際月費；測試主機已刪除 | ☐ |

---

> **附註**：本說明書依 2026-11-20 的實測與 Hermes 實際指令輸出撰寫（v2.1 已依指令核對修正）。
> Hermes 與各供應商持續更新，指令、價格與畫面可能改變，請以官方文件（`hermes-agent.nousresearch.com/docs`、`build.nvidia.com`）與 `hermes --help` 為準。