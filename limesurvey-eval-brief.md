# LimeSurvey 平台評估建議書（供另一個 AI 參考）

**文件目的**：讓另一個 AI 能在不了解我們環境的前提下，獨立評估「是否該用 LimeSurvey」以及「若要採用，該怎麼做」。
**撰寫依據**：2026-11 在一台 DigitalOcean droplet 上實際部署 LimeSurvey 7.11.0、建置 3 份問卷（含研究用雙模型問卷與 1 份 demo 問卷）、修過一次全站 502 事故後的實測經驗。
**文件性質**：技術建議，非規格書。文中每個「事實」都可重現；標 `待查證` 者為未核實數字，請勿直接引用。

---

## 0. 給評估者的三句話

1. **LimeSurvey 適合**：學術問卷、多語言、需要 token 名單／配額／條件邏輯、要能匯出 CSV/SPSS/R、預算近零。
2. **LimeSurvey 不適合**：需要複雜自適應實驗（adaptive/conjoint）、需要毫秒級前端互動、需要內建「匿名問卷＋隨機分派」的人。
3. **最大的坑不是功能，是「靜默預設值」**：必填、一題一頁、語言代碼、量表範圍都有預設值，錯了不會報錯，只會讓資料默默變形。本文第 6 節逐項列出。

---

## 1. 平台能力盤點（評估用）

### 1.1 強項（已實測）

| 能力 | 說明 | 實測結論 |
|---|---|---|
| 題型 | 28+ 種（單選、複選、陣列、評分、排序、數值、文字、上傳…） | `L / M / N / T / A / B / R / ;` 等可用；一題一頁 `format=S` 正常 |
| 多語言 | 同一問卷多語系，題目/選項/說明各自翻譯 | 必須用 `zh-Hant-TW`；用 `zh-Hant` 會被語言選單濾掉 |
| 條件邏輯 | `relevance` 運算式（例如 `RELIGION == 'OTH'`） | 可用；但題目代碼只能英數，底線會被剝除，運算式要同步改 |
| 配額 | `add_quota`，可設定上限與超額終止 | API 可用；配額「哪些答案計入」不在該函式內，需另設 |
| Token 名單 | 邀請碼、單次使用、屬性欄位 | 可用；但匿名問卷 (`anonymized=Y`) 會讓 `{TOKEN:ATTRIBUTE_n}` 變空字串 |
| 匯出 | CSV（含長/短欄名、代碼/答案文字）、SPSS、R、JSON | `export_responses` 可用；本版**沒有** `export_survey` |
| 遠端 API | JSON-RPC（`remotecontrol`） | 需先開 `RPCInterface=json` + `rpc_publish_api=1`，否則端點回空 |
| 自架 | Docker 單機即可跑，PHP 8.3 + MySQL 8 | 本機 2 vCPU / 4 GB 可跑；`待查證`：萬人級同時上線的資源需求 |
| 成本 | 開源（GPL），自架僅主機費 | 主機費用 `待查證`，勿引用未核實報價 |

### 1.2 限制（評估時務必確認是否踩到）

| 限制 | 影響 | 變通做法 |
|---|---|---|
| 匿名問卷不能讀 token 屬性 | 無法用 token 屬性做分派 | ①網址預填 `?SCEN=3&VER=2`（可被受試者改）②自建小型分派服務 302 轉址（建議） |
| 沒有 `export_survey` API | 無法用 API 匯出整份問卷結構 | 直接 dump MySQL 相關表，或人工下載 `.lss` |
| 沒有「逐題新增」API | 建問卷只能用整份 LSS 匯入 | 以程式產生 LSS（本文附範本） |
| 前端主題為 Bootstrap 4 基底 | 外觀調整需自寫 CSS | 自訂 CSS 掛在主題 `files_css`，**每個 sid 都要設**，預設繼承 vanilla 不含自訂 |
| 匿名＋Token 混用會壞 | 改成 `anonymized=N` 但回應表無 token 欄位 → 前台 500 | 不要走這條路，用外部服務 |
| 大量題目／長問卷 | 行動端體驗差、完成率掉 | 一題一頁 + 進度條；分群組；控制題數 |
| RPC 無「刪除單一答案」等細操作 | 只能用 SQL | 改 DB 前必備份，並同步寫回建置腳本 |

### 1.3 決策結論範本

> 若研究設計是「問卷量表 + 幾條條件邏輯 + 多語言 + 需要 token 名單與配額」，採 LimeSurvey，自架。
> 若設計含「隨機分派到不同刺激版本，且必須匿名」，LimeSurvey 單獨不夠，**必須**加一個伺服器端分派服務（約 100 行程式）。
> 若需要 adaptive testing、IRT、conjoint、即時反應時間，換平台（LimeSurvey 不擅長）。

---

## 2. 部署作法（自架，已驗證可行）

### 2.1 架構

```
Internet ──HTTPS──> Nginx（certbot 憑證）
                      └─ proxy_pass 127.0.0.1:3000
                            └─ Docker: limesurvey（acspri/limesurvey，PHP+Apache）
                                  └─ Docker network ──> mysql:3306（mysql:8.0）
```

- 對外只開 443；LimeSurvey 綁 `127.0.0.1:3000`，不直接曝露。
- 4 個 named volume：`/var/lime/sessions`、`/var/www/html/{plugins,upload,application/config}`。
- 資料只在 MySQL volume，**web 容器可安全重建**。

### 2.2 十條必守設定（都是踩過才知道）

1. **`--restart unless-stopped`**：否則主機重開機（例如 apt 升級換 kernel）後容器不會自己起來 → nginx 回 **502**，而且看起來像「網站壞了」。
2. **env 是 `config.php` 的唯一來源**：此 image 的 entrypoint 每次啟動都用環境變數重寫 `application/config/config.php`。改了密碼卻沒重建容器 → 重啟後必 **500**（`CDbConnection failed to open the DB connection`）。
3. **`LIMESURVEY_TABLE_PREFIX=lime_` 必須明示**：沒給會生成空前綴，實際表是 `lime_*` → 500 且訊息誤導為 `table settings_global not found`（不是缺表，是缺前綴）。
4. **DB 主機名 `mysql` 靠網路別名**：重建 web 容器時若沒帶 `--link`，或沒給 DB 容器長駐 alias，會出現 `getaddrinfo for host "mysql" ... Temporary failure in name resolution` 並無限等待。
5. **語言代碼用 `zh-Hant-TW`**（不是 `zh-Hant`），且映射要套在**整份 LSS 字串**上。
6. **`mandatory` 預設是 `N`**：不設就整份問卷可以全部跳過，畫面完全看不出來。
7. **`format` 預設 `G`（一組一頁）**：要一題一頁必須明確 `S`。
8. **`allowprev` 三值**：`Y` 開、`N` 關、`I` 繼承全域。關閉時說明頁要主動告知無法返回，否則受試者會抱怨。
9. **量表範圍屬研究決策**：不要為了「好看」把 4 點改 5 點，會動到已驗證量表的信效度。
10. **開機自檢**：用 systemd oneshot 在開機後檢查容器、本機 200、對外 200、反向代理與附屬服務，未起就拉起並寫 log。**不要靠人發現 502。**

### 2.3 重建 web 容器的正確姿勢

```bash
# 先留證據
docker inspect limesurvey limesurvey-mysql > container_snapshot_$(date +%F).json

docker rm -f limesurvey
docker run -d --name limesurvey --network limesurvey-net \
  -p 127.0.0.1:3000:80 --restart unless-stopped \
  -e LIMESURVEY_DB_TYPE=mysql -e LIMESURVEY_DB_HOST=mysql \
  -e LIMESURVEY_DB_PORT=3306 -e LIMESURVEY_DB_NAME=<db> \
  -e LIMESURVEY_DB_USER=<user> -e LIMESURVEY_DB_PASSWORD=<pw> \
  -e LIMESURVEY_TABLE_PREFIX=lime_ \
  -v <sessions>:/var/lime/sessions -v <plugins>:/var/www/html/plugins \
  -v <upload>:/var/www/html/upload -v <config>:/var/www/html/application/config \
  acspri/limesurvey
```

> **MySQL 容器不要重建**：它的 root 密碼 env 只在首次初始化生效，重建會動到資料目錄。只需 `docker update --restart unless-stopped <mysql>`。

### 2.4 持久性驗收（必做）

```bash
docker restart limesurvey          # 模擬重啟
# 等 200 後，確認自動生成的 config.php 內 password 與 tablePrefix 都正確
docker exec limesurvey sed -n '26,34p' /var/www/html/application/config/config.php
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3000/
```
**只看當下 200 不算修好**——若只改容器內檔案而沒改 env，下次重啟必復發。

---

## 3. 建問卷的兩條路徑

### 3.1 路徑 A：後台手工（適合 1 份、題目少、要調版面）

後台 `https://<host>/index.php/admin`（會自動跳 `authentication/sa/login`）。
優點：即時看外觀；缺點：無法版控、重建要重做、多人協作易衝突。

### 3.2 路徑 B：程式產生 LSS + RPC 匯入（建議）

流程：`build_*.py`（產生 LSS XML）→ `import_survey`（base64）→ `activate_survey` → 前台模擬 → `export_responses`。

```python
import base64, json, urllib.request

def rpc(url, method, params):
    req = urllib.request.Request(
        url, data=json.dumps({"method": method, "params": params, "id": 1}).encode(),
        headers={"Content-Type": "application/json"})
    return json.loads(urllib.request.urlopen(req, timeout=180).read().decode())

key = rpc(URL, "get_session_key", [USER, PASSWORD])["result"]
sid = rpc(URL, "import_survey", [key, base64.b64encode(xml.encode()).decode(), "lss", TITLE])["result"]
rpc(URL, "activate_survey", [key, int(sid)])
rpc(URL, "release_session_key", [key])
```

**LSS 最小骨架**（缺一節就匯入失敗）：

```xml
<document>
  <LimeSurveyDocType>Survey</LimeSurveyDocType>
  <DBVersion>718</DBVersion>              <!-- 必須與目標站 lime_settings_global 的 DBVersion 相同 -->
  <languages><language>zh-Hant-TW</language></languages>
  <surveys>…</surveys>                    <!-- sid/active/anonymized/format/language/… -->
  <surveys_languagesettings>…</surveys_languagesettings>
  <groups>…</groups><group_l10ns>…</group_l10ns>
  <questions>…</questions><question_l10ns>…</question_l10ns>
  <answers>…</answers><answer_l10ns>…</answer_l10ns>   <!-- 有選項才需要 -->
  <question_attributes>…</question_attributes>         <!-- min/max/display_rows 等 -->
</document>
```

**踩雷**：
- `DBVersion` 不對 → 匯入失敗或欄位缺失。先查：`SELECT stg_value FROM lime_settings_global WHERE stg_name='DBVersion';`
- 題目代碼只能英數，`SEN_1` 會被存成 `SEN1`；`relevance` 要跟著改。
- 匯入回傳的 `sid` 才是真的；**不要用 `SELECT MAX(sid)`**（sid 不單調）。
- `active='N'` 匯入後要另外 `activate_survey`；若曾用 SQL 手動改 `active`，回應表沒改名，之後啟用必失敗（需先把舊回應表 `RENAME`）。

---

## 4. 匿名問卷的分派（最容易低估的一段）

**問題**：`anonymized=Y` 時，表達式中的 `{TOKEN:ATTRIBUTE_n}` 一律被設為空字串，用 token 屬性分派完全無效。改成 `anonymized=N` 又會 500（回應表無 token 欄位）。

**方案比較**：

| 方案 | 作法 | 優點 | 缺點 |
|---|---|---|---|
| A. 網址預填 | `?SCEN=3&VER=2` 對應隱藏題 | 零開發 | 參數可見，受試者可自行改格 |
| B. 伺服器端分派（建議） | 小型 HTTP 服務依「目前最少、同分隨機、每格上限」選格，302 轉址到預填網址 | 不可篡改、可計配額 | 需部署服務 + Nginx 路由 |
| C. Token 名單 | 改非匿名 + token 屬性 | 原生支援 | 失去匿名性，倫理審查常打回 |

方案 B 的必要配套（三項都曾造成錯誤結果）：
1. 轉址的 `lang` 必須是 `zh-Hant-TW`。
2. 問卷未啟用時，服務要回「尚未開放」且**不建立保留名額**。
3. 換 sid 時全檔搜尋寫死的 sid，並清空保留檔。

**入口閘門**：Nginx 只開放 `/assign`，並用 map 擋掉沒有分派參數的 GET（`~^GET:(?!.*SCEN=)`→403）；只擋 GET，不擋 POST，避免作答中途失效。

> 注意：閘門也會擋後台預覽。預覽需帶參數（`?newtest=Y&lang=zh-Hant-TW&SCEN=4&VER=2`）；未啟用的問卷即使帶參數也回 401，**審閱用途請改由 DB 產生唯讀文件，不要為了預覽而啟用問卷**。

---

## 5. 驗證流程（缺一步就不算驗證完成）

以「建立 → 啟用 → 模擬作答 → 匯出」為完成標準：

1. **建立**：以 `import_survey` 回傳值為 sid。
2. **結構檢核**：題數、題型分佈、選項數、必填分佈、`format`、`allowprev`、語言列數、量表範圍。
3. **啟用**：`activate_survey`；回 `surveytablecreation` 時先查 `SHOW TABLES LIKE 'lime_%<sid>%'`（多為舊回應表已存在，不是題數太多）。
4. **模擬受試者**：取得歡迎頁 → 解析 `YII_CSRF_TOKEN` → POST `sid/move=movenext/lang` → 確認第一題與選項真的渲染（用 `question-container` 數量與選項文字，不要用 `document.title` 判斷）。
5. **匯出比對**：`export_responses` 讀回首行欄名，逐筆核對分派欄與答案欄。
6. **清理**：備份 → 刪測試回應 → 停止/刪除測試問卷 → 同步停用分派服務與 Nginx 路由。

> 每次 POST 開始都會產生一筆未完成回應（`submitdate` 為 NULL）。匿名問卷「完成」後 `submitdate` 會是 `1980-01-01 00:00:00`，**不是未完成**——判斷完成請用 `completed` 旗標或 `lastpage`。

---

## 6. 靜默失敗清單（給評估者的 checklist）

以下每一項「預設值」都曾在沒有錯誤訊息的情況下讓資料變形：

- [ ] `mandatory` 是否每題都設了？
- [ ] `format` 是 `S`（一題一頁）還是預設 `G`？
- [ ] `allowprev` 是 `Y/N/I` 哪一個？說明頁有沒有告知？
- [ ] 語言代碼是否 `zh-Hant-TW`？每個語言的 `l10n` 列數是否等於題數？
- [ ] `question_theme_name` 與題型視圖是否相符（`listradio` 只能用 `listradio` 主題）？
- [ ] 自訂 CSS 是否逐 sid 寫入 `files_css`（預設 `inherit` 不含自訂）？
- [ ] 必填題在「不作答按下一步」時是否真的被擋下、每題有 Required？
- [ ] 量表每個分數都有文字標示（不只標兩端）？
- [ ] 匿名問卷是否誤用 token 屬性分派？
- [ ] 備份是不是真的：`mysqldump` 指定不存在的表會產生只有表頭的小檔且不一定報錯 → 要檢查檔案大小與 `INSERT INTO` 數量。

---

## 7. 給評估 AI 的具體問題清單

評估時請逐項回答，答案會直接決定「能不能用 LimeSurvey」：

1. 研究設計是否需要**隨機分派**？分派單位是「人」還是「題／情境」？（前者可用外部服務，後者需要 within-subject 設計＋混合模型）
2. 是否必須**匿名**？若必須匿名又要分派 → 走本文 §4 方案 B。
3. 題數與頁數上限？預估完成時間？（超過 15 分鐘，完成率通常明顯下降 `待查證`）
4. 需要**配額**嗎？配額維度是什麼？超額時要終止或轉址？
5. 需要 token 名單（一對一邀請）嗎？需要追蹤未完成者嗎？
6. 需要哪些匯出格式？下游分析工具是 R / SPSS / Python？
7. 樣本規模與同時上線人數？是否有主機資源上限？
8. 倫理審查是否要求「提交後可撤回」？匿名問卷技術上做不到，需在說明頁誠實告知。
9. 是否需要多語言？哪些語系？（`zh-Hant-TW` / `en` / `ja` 已實測）
10. 誰維護？有沒有能力處理 Docker/nginx/憑證更新？

---

## 8. 成本與風險（請自行核實）

| 項目 | 說明 |
|---|---|
| 授權 | GPL 開源，無授權費 |
| 主機 | 自架需一台可跑 Docker 的 VPS；規格與費用 `待查證`（勿引用未核實報價） |
| 人力 | 一次性建置約半天；每月維護（憑證、備份、升級）約 1 小時 |
| 資料風險 | 自架＝自己負責備份與加密；建議每日 `mysqldump` + 異地備份，且備份檔需驗證內容 |
| 升級風險 | image 升級可能改變 entrypoint 行為（本案 config.php 生成邏輯即為一例）→ 升級後必做 §2.4 驗收 |
| 鎖定風險 | 低。資料在 MySQL，`.lss` 可攜；但客製分派服務與自訂 CSS 屬自建資產，需一併文件化 |

---

## 9. 結論建議

- **推薦採用**：學術問卷、多語言、需 token／配額、要能自控資料落地。
- **採用但需加件**：需要匿名＋隨機分派 → 加一個約 100 行的分派服務（本文 §4）。
- **不建議**：需要 adaptive/conjoint/反應時間量測、或無力維護伺服器者 → 改用託管服務或雲端問卷平台。
- **務必先做**：把 §6 的 checklist 變成自動化檢核腳本，建置後每次跑；並把 §2.4 的重啟驗收列入上線清單。這兩個動作能在無人察覺的情況下擋掉大部分事故。

---

### 附錄 A：常用 RPC 方法（本版 7.11 實測存在）

`get_session_key`、`release_session_key`、`import_survey`、`activate_survey`、`deactivate_survey`、`delete_survey`、`set_survey_properties`、`set_language_properties`、`export_responses`、`add_quota`、`activate_tokens`。
（未知方法名會回 HTTP 500 而非 404；呼叫前可先 `grep 'public function' .../remotecontrol_handle.php` 確認。）

### 附錄 B：容器內查 DB 的正確姿勢

```bash
docker exec <mysql>  mysql --default-character-set=utf8mb4 -u root -p'<pw>' -N <db> -e "…" 2>&1 | grep -v Warning
```
少了 `--default-character-set=utf8mb4`，中文欄位會變成 `???`，會被誤判為「標題／題目壞掉」。

---

**文件版本**：1.0（2026-11-24）
**可重現性**：本文所有結論均來自 2026-11 的實機操作與逐項驗證，非推測；未核實者已標 `待查證`。