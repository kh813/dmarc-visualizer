# dmarc-visualizer

[English](#english) | [日本語](#日本語)

---

<a name="english"></a>
## English

Analyse and visualize DMARC results using lightweight, modern open-source tools.

- **[parsedmarc](https://github.com/domainaware/parsedmarc)** for parsing DMARC and SMTP-TLS reports.
- **[PostgreSQL](https://www.postgresql.org/)** for lightweight, persistent data storage (replaces Elasticsearch for minimal RAM usage and zero Java dependencies).
- **[Grafana](https://grafana.com/)** for dashboards and visual reporting.

---

### Features

- **Ultra-lightweight & Low Memory**: Uses PostgreSQL (`postgres:16-alpine`), consuming less than 100 MB RAM in total (over 90% reduction compared to Elasticsearch). No Java/JVM required.
- **Side-by-side Testing**: Ports and database credentials are fully configurable via `.env` (defaults to standard Grafana port `3000`. If testing side-by-side with an existing service on port 3000, simply change `GRAFANA_PORT=3000` in `.env`).
- **Official Dashboard Included**: Pre-configured with the official Grafana 10/11 DMARC dashboard for PostgreSQL.
- **Auto-adapts Legacy Configs**: You can directly copy your existing `parsedmarc.ini` — legacy `[elasticsearch]` sections are automatically disabled, and PostgreSQL connections are configured seamlessly.
- **Convenient Management Script (`app.sh`)**: Start, stop, restart, check memory status, parse reports, and prune old data with single commands.
- **Flexible Access Control**: Defaults strictly to local-only access (`127.0.0.1`) while offering seamless integration with Cloudflare Tunnel.

---

### Resource & Memory Comparison (30 Days Retention)

Below is an estimated real-world comparison of running `dmarc-visualizer` retaining **30 days** of DMARC report data:

| Component | **Legacy Stack (Elasticsearch 7.x)** | **This Fork (PostgreSQL 16)** | Difference |
| :--- | :--- | :--- | :--- |
| **Database Engine** | **~1.5 GB – 2.5 GB+** | **~35 MB – 60 MB** | **~97% reduction** |
| **Grafana (Web Dashboard)** | ~100 MB – 150 MB | ~75 MB – 90 MB | Legacy plugins removed |
| **Total Resident Memory (RAM)** | **~1.6 GB – 2.7 GB+** | **~110 MB – 150 MB** | **~95% overall reduction** |
| **Minimum Hardware Required** | 2 GB – 4 GB RAM VPS | **512 MB – 1 GB RAM VPS / Raspberry Pi** | Runs on cheapest instances |

#### Why is PostgreSQL so much lighter?
1. **Zero Java/JVM Overhead:** Elasticsearch allocates a fixed Java Heap of at least 1 GB upon launch, plus operating system page caches. PostgreSQL (written in C) allocates memory dynamically as needed and starts at only ~25 MB.
2. **No Daily Index/Shard Accumulation:** `parsedmarc` creates separate daily indices (`dmarc_aggregate-YYYY-MM-DD`). In Elasticsearch, 30 days means 30+ open shards with Lucene terms dictionaries pinned in memory. In PostgreSQL, all data lives in standard tables indexed by clean B-Trees, adding negligible memory overhead for 30 days of data.
3. **Safe from OOM Crashes:** Older setups frequently suffered from Out-Of-Memory (OOM) kills on modest servers. The PostgreSQL stack comfortably runs alongside your other services without resource competition.

---

### Quick Start

#### 1. Start Services
```bash
./app.sh start
```
By default, this will spin up PostgreSQL (internalized) and Grafana on port `3000`.

#### 2. Parse DMARC Reports
Place your DMARC XML/zip/gz reports into the `files/` directory, then run:
```bash
./app.sh parse
```
`parsedmarc` will parse all files in `files/`, save records to PostgreSQL, and update Grafana.

#### 3. Open Grafana Dashboard
Access Grafana in your web browser at:
👉 **http://localhost:3000** (or http://<LAN-IP>:3000)
- Navigate to **Dashboards > DMARC Reports — PostgreSQL**

---

### Configuration

#### Environment Variables (`.env`)
Configuration is managed via `.env`. A template is provided in `.env.example`:

```bash
# Web UI binding (Default: 0.0.0.0 - accessible from local host and LAN devices)
GRAFANA_BIND_IP=0.0.0.0
GRAFANA_PORT=3000

# PostgreSQL binding (Default: 127.0.0.1 for maximum security - LAN access to DB is blocked)
POSTGRES_BIND_IP=127.0.0.1
POSTGRES_PORT=5433

# PostgreSQL Database Credentials
POSTGRES_DB=dmarc
POSTGRES_USER=parsedmarc
POSTGRES_PASSWORD=parsedmarc_password

# Grafana Admin Credentials (applied only on the very first start; see "Changing the Grafana Admin Password")
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=admin

# Cloudflare Tunnel Integration (Optional)
# GRAFANA_ROOT_URL=https://dmarc.example.com
# CLOUDFLARE_TUNNEL_NETWORK=cloudflared_net
```

#### Custom `parsedmarc.ini` (Optional)
If you do not provide a `parsedmarc.ini`, one will be automatically generated from your `.env` settings.
If you need advanced features like **automated IMAP/Exchange mailbox polling**, place your file at `parsedmarc/parsedmarc.ini` (or the project root):

```ini
[general]
# Save daily statistical aggregate reports (rua) to database
save_aggregate = True
# Save individual failure/forensic reports (ruf) for phishing & incident investigation
# (Note: Malicious attachment payloads are automatically stripped for security)
save_forensic = True
output = /output/

# Optional: Fetch DMARC reports automatically from an IMAP mailbox
[imap]
host = imap.example.com
port = 993
ssl = True
user = dmarc@example.com
password = your-imap-password

# Folder & processing options belong in [mailbox] (not [imap]) since parsedmarc 8.0
[mailbox]
watch = True
delete = False
# reports_folder = INBOX      # Folder to read reports from (default: INBOX)
# archive_folder = Archive    # Folder to move processed reports to (default: Archive)
#                             # Use "/" as separator, without "INBOX." prefix (e.g. Archive/Aggregate)
# batch_size: Number of messages to fetch & process per batch before writing to DB (default: 10).
# Keeping this small (e.g. 5-20) prevents RAM spikes when thousands of unread reports exist.
batch_size = 10
```

> [!TIP]
> **Peak Memory Control (`batch_size`)**: If your mailbox has accumulated thousands of unread reports, `batch_size = 10` ensures `parsedmarc` loads, parses, saves to PostgreSQL, and frees memory in small chunks. This keeps peak RAM usage below ~100MB even under heavy volume. (Legacy configs with `watch` / `batch_size` / `reports_folder` / `archive_folder` under `[imap]` still work with a deprecation warning, but `delete` under `[imap]` is silently ignored — move these options to `[mailbox]`.)


---

### Network & Access Control (LAN Access vs Local-Only vs Cloudflare Tunnel)

By default, the stack is configured with security in mind:
- **Web UI (Grafana)**: Binds to `0.0.0.0:3000` so it is accessible from your local host AND other devices on your LAN (e.g. `http://<LAN-IP>:3000`). Passwordless viewing is enabled by default.
- **Database (PostgreSQL)**: Fully internalized inside Docker's isolated network (`5432/tcp`). No host ports are exposed at all, completely eliminating direct network attack vectors.
- **Malware Protection**: Automatically strips dangerous email attachments and payload blobs from forensic failure reports (`--strip-attachment-payloads`), storing only report metadata.

#### Option A: Standard Setup (Web on LAN, Database Fully Internal)
In `.env`:
```bash
GRAFANA_BIND_IP=0.0.0.0
```
- Dashboard is reachable from other PCs or smartphones on your Wi-Fi/LAN.
- PostgreSQL database is strictly isolated inside the Docker network.

#### Option B: Strict Local-Only Web Access (Lockdown)
If you want to forbid LAN devices from accessing even the web UI:
In `.env`:
```bash
GRAFANA_BIND_IP=127.0.0.1
```
Grafana binds strictly to `127.0.0.1`. External devices on LAN cannot access it.

#### Option C: Access via Cloudflare Tunnel (Recommended: Docker Shared Network)
Route directly through Docker's internal network **without opening any host ports to the LAN or internet**:
1. In `.env`:
   ```bash
   CLOUDFLARE_TUNNEL_NETWORK=my_tunnel_network
   GRAFANA_ROOT_URL=https://dmarc.example.com
   ```
2. Restart: `./app.sh restart`
3. In Cloudflare Tunnel ingress rules:
   ```yaml
   ingress:
     - hostname: dmarc.example.com
       service: http://grafana:3000
   ```

#### Changing the Grafana Admin Password
Anonymous viewing (`GRAFANA_ANONYMOUS_ENABLED=true`) does **not** disable the admin login. With the default `admin` / `admin`, anyone who can reach the Web UI (e.g. any device on your LAN with Option A) can sign in as Grafana admin and edit dashboards, manage users, or query the database through the data source. Change it unless the Web UI is reachable only by you.

- **Before the first start**: set `GRAFANA_ADMIN_PASSWORD` in `.env`.
- **After the first start**: changing `.env` has **no effect**. Grafana applies `GRAFANA_ADMIN_PASSWORD` only when its database (the `grafana_data` volume) is created for the first time. Reset it with the Grafana CLI instead:
  ```bash
  # The password is typed without echo and never appears in shell history
  read -rsp 'New Grafana admin password: ' PW; echo
  printf '%s\n' "$PW" | docker compose exec -T grafana grafana cli admin reset-admin-password --password-from-stdin
  unset PW
  ```
  Or sign in as admin and use **Profile > Change password** in the Web UI.

  The new password is stored (hashed) only in Grafana's database; `.env` is not updated, and keeping the old value there does no harm. If you remove the `grafana_data` volume (e.g. `docker compose down -v`), Grafana is re-initialized from `.env` again.

#### Security Roadmap (Planned Future Hardening)
- [ ] **Mandatory Authentication**: Option to disable anonymous viewer mode (`GRAFANA_ANONYMOUS_ENABLED=false`) with user password or Cloudflare Access SSO.
- [ ] **Non-root Container Execution**: Run `parsedmarc` under an unprivileged user (Least Privilege Principle).
- [ ] **Default Password Warning**: Interactive warning when running with default `admin` credentials.

---

### Management Script (`./app.sh`)

| Command | Description |
| :--- | :--- |
| **`./app.sh start`** (or `up`) | Starts PostgreSQL and Grafana containers in the background. |
| **`./app.sh stop`** (or `down`) | Stops all running containers. |
| **`./app.sh restart`** | Restarts all services. |
| **`./app.sh status`** (or `ps`) | Displays container status and real-time RAM/CPU resource consumption. |
| **`./app.sh logs [service]`** | Follows container logs in real time (e.g., `./app.sh logs grafana`). |
| **`./app.sh parse`** | Parses all DMARC reports in `./files/` into the database. |
| **`./app.sh prune [days] [-y]`** | Prunes reports older than N days (default: 90 days). Use `-y` for cron / non-interactive. |
| **`./app.sh clean-files`** | Clears temporary files from `./files/` and `./output_files/`. |
| **`./app.sh clean-all`** | Completely purges containers and database volumes (factory reset). |
| **`./app.sh psql`** | Opens an interactive `psql` command-line shell to the PostgreSQL database. |

#### Automation (Cron Examples)
Edit crontab with `crontab -e`:

```bash
# 1. Parse new reports every hour
0 * * * * cd /path/to/dmarc-visualizer && ./app.sh parse >> /var/log/dmarc-parse.log 2>&1

# 2. Delete reports older than 180 days every Sunday at 03:00 AM
0 3 * * 0 cd /path/to/dmarc-visualizer && ./app.sh prune 180 -y >> /var/log/dmarc-prune.log 2>&1
```

---

### Migration Guide (From Legacy DMARC Visualizer)

#### Q: Will copying my old `parsedmarc.ini` work directly?
**Yes, you can copy it directly.**
The entrypoint script automatically detects legacy `[elasticsearch]` sections and disables them, while injecting the new `[postgresql]` settings.

#### Step-by-Step Migration:
1. **Deploy side-by-side (Optional):** If your legacy stack is currently using port 3000, set `GRAFANA_PORT=3001` in `.env` to avoid port collision.
2. **Copy configuration:** `cp /path/to/old/parsedmarc/parsedmarc.ini parsedmarc/parsedmarc.ini`
3. **Start new stack:** `./app.sh start`
4. **Import historical reports:** `cp /path/to/old/files/* files/ && ./app.sh parse`
5. **Verify in Grafana:** Open `http://localhost:3000` (or `3001` if changed) and verify the dashboard.
6. **Retire legacy stack:** Stop old stack (`docker compose down -v`), change `GRAFANA_PORT=3000` in `.env` if desired, and run `./app.sh restart`.

---
---

<a name="japanese"></a>
## 日本語

オープンソースの最新軽量スタックを用いた DMARC 解析・可視化ツールです。

- **[parsedmarc](https://github.com/domainaware/parsedmarc)**: DMARC および SMTP-TLS レポートの解析エンジン
- **[PostgreSQL](https://www.postgresql.org/)**: 軽量・永続ストレージ（Elasticsearch を廃止し、Java 依存を排除して省メモリ化）
- **[Grafana](https://grafana.com/)**: レポート可視化ダッシュボード

---

### 特徴

- **超軽量・省メモリ**: PostgreSQL (`postgres:16-alpine`) を採用し、スタック全体で 100 MB 未満の RAM で動作（Elasticsearch 比で 90% 以上削減）。Java / JVM は不要です。
- **既存環境との並行テスト**: デフォルトは標準の 3000 番ポートです。旧環境が 3000 番を使用中の場合でも、`.env` で `GRAFANA_PORT=3001` に変更すれば並行してテスト可能です。
- **公式 PostgreSQL ダッシュボード内蔵**: Grafana 10/11 向けの公式 DMARC ダッシュボードをリポジトリ内にプリセット済みです。
- **旧設定ファイルの自動適応**: 従来の `parsedmarc.ini` をそのままコピーするだけで動作します。古い `[elasticsearch]` 設定は自動で無効化され、PostgreSQL 接続設定が自動補完されます。
- **便利な管理スクリプト (`app.sh`)**: 起動、停止、再起動、メモリ消費量確認、レポート解析、古いデータの削除をワンコマンドで実行できます。
- **安全なアクセス制御**: デフォルトでローカル限定（`127.0.0.1`）に制限されており、必要に応じて Cloudflare Tunnel とも安全に連携可能です。

---

### リソース・メモリ消費量の比較（30日分保持時）

一般的な運用規模（数ドメイン、1日数百〜数千通）で **30日分の DMARC データを保持・検索した場合の見込み RAM 使用量** です：

| コンポーネント | **旧スタック (Elasticsearch 7.x)** | **本フォーク (PostgreSQL 16)** | 削減効果 |
| :--- | :--- | :--- | :--- |
| **データベース本体** | **約 1.5 GB 〜 2.5 GB+** | **約 35 MB 〜 60 MB** | **約 97% 削減** |
| **Grafana (Web画面)** | 約 100 MB 〜 150 MB | 約 75 MB 〜 90 MB | プラグイン不要化で軽量化 |
| **全体合計 (常駐RAM)** | **約 1.6 GB 〜 2.7 GB+** | **約 110 MB 〜 150 MB** | **約 95% 削減** |
| **推奨ハードウェアスペック**| 最低 2 GB 〜 4 GB RAM の VPS | **512 MB 〜 1 GB RAM の格安VPS / ラズパイ** | 最安値サーバーで余裕で動作 |

#### なぜ PostgreSQL はこれほど軽いのか？
1. **JVM (Java仮想マシン) のオーバーヘッドがゼロ:** Elasticsearch は起動するだけで最低 1 GB のヒープメモリを確保しますが、PostgreSQL (C言語製) は起動時わずか 25 MB 程度で、必要な分だけメモリを使います。
2. **日次シャード蓄積問題の解消:** `parsedmarc` は日付ごとにインデックスを分割するため、Elasticsearch では 30 日分で 30 個以上のシャードがメモリを圧迫します。PostgreSQL では単一テーブルに B-Tree インデックスを張るだけなので、30日分蓄積してもメモリ増加はごくわずかです。
3. **OOM (メモリ不足クラッシュ) からの解放:** メモリの少ないサーバーで頻発していた OOM Killer による突然のコンテナ強制終了を防止し、他のアプリと安全に共存できます。

---

### クイックスタート

#### 1. サービスの起動
```bash
./app.sh start
```
PostgreSQL（内部）と Grafana（標準ポート `3000`）が起動します。

#### 2. DMARC レポートのパース実行
解析したい DMARC レポート（XML, zip, gz）を `files/` ディレクトリに配置し、以下を実行します：
```bash
./app.sh parse
```
`files/` 内の全ファイルがパースされ、PostgreSQL へ保存されて Grafana に反映されます。

#### 3. Grafana ダッシュボードを開く
ブラウザで以下にアクセスします：
👉 **http://localhost:3000** (または http://<LAN-IP>:3000)
- **Dashboards > DMARC Reports — PostgreSQL** を開きます。

---

### 設定

#### 環境変数 (`.env`)
`.env` ファイルでポートや認証情報を設定します（テンプレート: `.env.example`）：

```bash
# Web 画面のバインド (デフォルト: 0.0.0.0 で LAN 内の他端末からもアクセス可能)
GRAFANA_BIND_IP=0.0.0.0
GRAFANA_PORT=3000

# PostgreSQL のバインド (デフォルト: 127.0.0.1 でホスト自身に限定、LAN からの DB アクセスは遮断)
POSTGRES_BIND_IP=127.0.0.1
POSTGRES_PORT=5433

# PostgreSQL 認証情報
POSTGRES_DB=dmarc
POSTGRES_USER=parsedmarc
POSTGRES_PASSWORD=parsedmarc_password

# Grafana 管理者情報（反映されるのは初回起動時のみ。「Grafana 管理者パスワードの変更」を参照）
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=admin

# Cloudflare Tunnel 連携設定 (任意)
# GRAFANA_ROOT_URL=https://dmarc.example.com
# CLOUDFLARE_TUNNEL_NETWORK=cloudflared_net
```

#### カスタム `parsedmarc.ini` (任意)
`parsedmarc.ini` を用意しない場合でも、`.env` の設定から自動生成されます。
**IMAP / メールボックスによるメール自動受信** など高度な設定を行う場合は、`parsedmarc/parsedmarc.ini`（またはプロジェクト直下）に配置してください：

```ini
[general]
# 日次集計統計レポート (rua) をデータベースに保存
save_aggregate = True
# 個別の認証失敗・なりすまし調査用レポート (ruf) をデータベースに保存
# （危険な添付ファイルバイナリは自動的に無害化・除去されます）
save_forensic = True
output = /output/

# 任意: IMAP メールボックスからレポートを自動取得
[imap]
host = imap.example.com
port = 993
ssl = True
user = dmarc@example.com
password = your-imap-password

# フォルダ・処理方法の設定は parsedmarc 8.0 以降 [imap] ではなく [mailbox] に書きます
[mailbox]
watch = True
delete = False
# reports_folder = INBOX      # レポート読み込み元フォルダ（デフォルト: INBOX）
# archive_folder = Archive    # 処理済みメール移動先フォルダ（デフォルト: Archive）
#                             # 区切りは "/"、"INBOX." は付けない（例: Archive/Aggregate）
# batch_size: 1回に取得・パースしてDBに保存するメール件数（デフォルト: 10）
# 未読メールが数千通溜まっている場合でも、小さく設定（5〜20）することでメモリの急上昇（スパイク）を防ぎます。
batch_size = 10
```

> [!TIP]
> **ピークメモリの抑制 (`batch_size`)**: メールボックス内に大量のレポートメールが溜まっている場合でも、`batch_size = 10` を設定することで「小分けに取得 → パース → PostgreSQLに保存 → メモリ解放」のサイクルを繰り返すため、大量処理時でもピークメモリを常に数十MB〜100MB程度に抑えられます。旧形式（`[imap]` に `watch` / `batch_size` / `reports_folder` / `archive_folder` を記述）も警告付きで動作しますが、`[imap]` 内の `delete` は無視されるため、これらは `[mailbox]` へ移してください。

---

### ネットワーク & アクセス制御（LAN アクセス vs 完全ローカル vs Cloudflare Tunnel）

セキュリティを考慮した標準構成となっています：
- **Web 画面 (Grafana)**: `0.0.0.0:3000` でリッスンし、ホストマシン自身および LAN 内の別端末（スマホや別 PC: `http://<ホストのLAN-IP>:3000`）からアクセスできます。デフォルトではパスワードなしで閲覧可能です。
- **データベース (PostgreSQL)**: Docker 内部ネットワーク（`5432/tcp`）に完全に隔離され、**ホスト側のポートは一切公開されません**。外部ネットワークからの直接攻撃リスクを完全に排除しています。
- **マルウェア防御**: DMARC 失敗レポートに含まれる危険なメール添付ファイルやペイロードバイナリを自動除去（`--strip-attachment-payloads`）し、メタデータのみを安全に保存します。

#### オプション A: 標準設定（Web は LAN 内公開、DB は完全内部化・推奨）
`.env` の設定：
```bash
GRAFANA_BIND_IP=0.0.0.0
```
- ブラウザ画面は LAN 内のどの端末からでも閲覧可能。
- データベースは Docker 内部に隔離され、ホストや LAN にポートを晒さないため安全。

#### オプション B: Web 画面も完全ローカル限定にする場合（完全ロックダウン）
LAN 内の他端末からの Web 画面アクセスも禁止したい場合：
```bash
GRAFANA_BIND_IP=127.0.0.1
```

#### オプション C: Cloudflare Tunnel 経由でのアクセス（推奨: Docker 共有ネットワーク方式）
ホストマシンのポートを LAN やインターネットに開けることなく、Docker 内部ネットワーク経由で安全に公開できます：

1. `.env` を設定：
   ```bash
   CLOUDFLARE_TUNNEL_NETWORK=my_tunnel_network
   GRAFANA_ROOT_URL=https://dmarc.example.com
   ```
2. 再起動: `./app.sh restart`
3. Cloudflare 側の Ingress ルールに以下を追加：
   ```yaml
   ingress:
     - hostname: dmarc.example.com
       service: http://grafana:3000
   ```

#### Grafana 管理者パスワードの変更
匿名閲覧（`GRAFANA_ANONYMOUS_ENABLED=true`）にしていても、**管理者ログインは無効になりません**。初期値の `admin` / `admin` のままだと、Web 画面に届く人（オプション A なら LAN 内のどの端末からでも）が Grafana 管理者としてログインでき、ダッシュボードの編集・ユーザー管理・データソース経由でのデータベース参照ができてしまいます。Web 画面に自分しかアクセスできない環境でなければ変更してください。

- **初回起動の前**: `.env` の `GRAFANA_ADMIN_PASSWORD` を設定します。
- **初回起動の後**: `.env` を書き換えても**反映されません**。`GRAFANA_ADMIN_PASSWORD` が使われるのは、Grafana のデータベース（`grafana_data` ボリューム）が初めて作られるときだけです。Grafana CLI でリセットします：
  ```bash
  # 入力したパスワードは画面に表示されず、シェル履歴にも残りません
  read -rsp 'New Grafana admin password: ' PW; echo
  printf '%s\n' "$PW" | docker compose exec -T grafana grafana cli admin reset-admin-password --password-from-stdin
  unset PW
  ```
  または、admin でログインして Web 画面の **Profile > Change password** から変更できます。

  新しいパスワードは Grafana のデータベースにハッシュとして保存されるだけで、`.env` は更新されません（`.env` に古い値が残っていても問題ありません）。`docker compose down -v` などで `grafana_data` ボリュームを削除すると、`.env` の値で初期化し直されます。

#### 今後のセキュリティ強化計画 (Roadmap)
- [ ] **ログイン認証の必須化**: 匿名閲覧モードの無効化（`GRAFANA_ANONYMOUS_ENABLED=false`）と、パスワードまたは Cloudflare Access (SSO) 連携の容易化。
- [ ] **非 root ユーザー実行**: `parsedmarc` コンテナの非特権ユーザー（Rootless）実行。
- [ ] **デフォルトパスワード警告**: 初期パスワード（`admin`）のまま本番稼働している場合の自動注意喚起。

---

### 管理スクリプト (`./app.sh`)

| コマンド | 説明 |
| :--- | :--- |
| **`./app.sh start`** (または `up`) | バックグラウンドで全サービスを起動 |
| **`./app.sh stop`** (または `down`) | 全サービスを停止 |
| **`./app.sh restart`** | 全サービスを一括再起動 |
| **`./app.sh status`** (または `ps`) | 稼働状況およびリアルタイムのメモリ・CPU 使用量を表示 |
| **`./app.sh logs [service]`** | ログをリアルタイム表示（例: `./app.sh logs grafana`） |
| **`./app.sh parse`** | `./files/` 内の全レポートをパースして DB へ投入 |
| **`./app.sh prune [days] [-y]`** | 指定日数（デフォルト: 90日）より古いレポートを削除。`-y` で確認省略 |
| **`./app.sh clean-files`** | `./files/` および `./output_files/` 内の一時ファイルを削除 |
| **`./app.sh clean-all`** | コンテナおよび DB ボリュームを完全消去（工場出荷リセット） |
| **`./app.sh psql`** | PostgreSQL の対話型 `psql` シェルに接続 |

#### 定期実行の自動化 (Cron 設定例)
`crontab -e` でホストマシンの cron に登録します：

```bash
# 1. 毎時 0 分に新着レポートを自動パース
0 * * * * cd /path/to/dmarc-visualizer && ./app.sh parse >> /var/log/dmarc-parse.log 2>&1

# 2. 毎週日曜 午前 3 時に 180 日を超えた古いレポートを自動削除
0 3 * * 0 cd /path/to/dmarc-visualizer && ./app.sh prune 180 -y >> /var/log/dmarc-prune.log 2>&1
```

---

### 旧 DMARC Visualizer からの移行ガイド

#### Q: 旧バージョンの `parsedmarc.ini` をそのままコピーして動きますか？
**はい、そのままコピーして動作します。**
起動スクリプトが旧設定内の `[elasticsearch]` を自動で無効化し、新しい `[postgresql]` 接続設定を自動補完します。

#### ステップ・バイ・ステップ移行手順:
1. **並行デプロイ（任意）:** 旧環境がすでに 3000 番ポートを使用している場合は、新環境の `.env` で `GRAFANA_PORT=3001` に設定して競合を回避できます。
2. **設定のコピー:** `cp /path/to/old/parsedmarc/parsedmarc.ini parsedmarc/parsedmarc.ini`
3. **新スタックの起動:** `./app.sh start`
4. **過去レポートのインポート:** `cp /path/to/old/files/* files/ && ./app.sh parse`
5. **Grafana で動作確認:** `http://localhost:3000`（ポート変更時はそのポート）を開いてダッシュボードを確認。
6. **旧スタックの停止・移行完了:** 旧環境を停止（`docker compose down -v` で数GBのストレージ・メモリを解放）。必要に応じて新環境の `.env` で `GRAFANA_PORT=3000` に変更し、`./app.sh restart` で完了です。
