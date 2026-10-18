# AGENTS.md - JPEG_TOP プロジェクト開発ルール

本ドキュメントは、本リポジトリ（JPEGエンコーダー・デコーダー RTL開発環境）において、AIエージェントおよび開発者が遵守すべき全体規範、ディレクトリ役割分担、および各設計工程の基本ルールを定めたものです。

---

## 1. プロジェクト概要と基本方針

### 1.1 プロジェクトの目的
- **AIによるVerilog (RTL) 設計・検証の実証**
- Baseline Sequential JPEG（YCbCr 4:4:4 / 4:2:2 / 4:2:0、8bit、単一scan）のエンコーダーおよびデコーダーをVerilog-2001で実装・検証する。
- エンコードとデコードは**排他動作（同時動作なし）**とし、算術・バッファ等のハードウェア資源を共有する。

### 1.2 CPUとRTLの処理分担
- **CPU（ソフトウェア／テスト環境で模擬）**:
  - JPEGヘッダ（SOI, DQT, DHT, SOF0, SOS, DRI, EOI等）のパースおよび生成
  - 色空間変換（RGB ↔ YCbCr）、サブサンプリング、ラスタ／planar配置
  - 量子化テーブル・Huffmanテーブルの計算・整列およびAPB経由でのロード
  - DRAMバッファ（base/stride）の確保・整列（8byteアラインメント）およびDMA設定
- **RTL（ハードウェア回路）**:
  - 圧縮scanデータ／画像ブロックのAXI4 DMA入出力
  - DCT／IDCT（2D 8x8直交変換）
  - 32段パイプライン除算器による量子化／逆量子化
  - Huffman符号化／復号（bitstreamパディング、byte stuffing FF00処理、DRI/RSTマーカー処理）

### 1.3 主要性能・制約目標
- **動作周波数**: 256 MHz
- **処理速度**: A4・300 dpi（2480×3508画素、8,699,840画素/ページ）の模擬原稿にて **100 ppm** 相当
  - RTLサイクル予算: 4:4:4時に最大 **153,600,000 cycle/ページ**（ブロックあたり約376 cycle）
- **AXI4 I/F条件**: 64bitデータ幅、リード／ライト平均レイテンシ各500 ns（256 MHz換算で128 cycle）、最大8 outstanding

---

## 2. ディレクトリ構成と役割分担

リポジトリ直下の各フォルダは以下の通り明確に責務が分離されています。

| ディレクトリ | 役割と責務 | 主なファイル・成果物 |
|---|---|---|
| `docs/` | **要件定義・設計仕様・検証記録** | `requirements.md`（要件定義）<br>`design_spec.md`（全体設計・接続図）<br>`blocks/`（ブロック別仕様書）<br>`blocks/rtl_contract.md`（RTL実装契約）<br>`rtl_interfaces.md`（内部I/F仕様）<br>`restart_decode.md`（拡張仕様）<br>`implementation_handoff.md`（引き継ぎ書）<br>`implementation_status.md`（実装状況・残課題）<br>`validation_results.md`（検証記録・実測値） |
| `rtl/` | **合成可能 Verilog RTL ソースコード** | `jpeg_top.v`（トップモジュール）<br>`jpeg_*.v`（各ブロック回路モジュール）<br>`jpeg_defs.vh`（共通定数・レジスタ・エラー定義）<br>`jpeg_c.vh`（DCT/IDCT変換定数）<br>`jpeg_zigzag.vh`（ジグザグ走査テーブル） |
| `sim/` | **シミュレーション・テストベンチ** | `top_tb.sv`（トップ統合検証環境）<br>`numeric_tb.sv`, `bitstream_tb.sv`, `dma_tb.sv`, `storage_tb.sv`, `width_tb.sv`, `apb_tb.sv`, `jpeg_tool_tb.sv`（SystemVerilog TB）<br>`sim/README.md`（テスト環境詳細） |
| `tools/` | **参照モデル・生成・判定スクリプト** | `generate_vectors.py`, `generate_rtl_tables.py`（ベクタ・テーブル生成）<br>`check_interop.py`（外部JPEG/Pillow相互運用判定）<br>`generate_performance_decode.py`, `check_performance.py`（A4性能評価）<br>`generate_manuscript.py`（模擬原稿生成）<br>`jpeg_encode.py`, `jpeg_decode.py`（CLI画像変換ツール） |
| `tests/data/` | **テストデータ・生成条件** | 再生成可能な入力データバイナリ（`.bin`）、画像（`.png`）、条件記述（`.json`） |
| `build/` | **ビルド・実行時生成物（Git管理外）** | Questa Simコンパイル成果物（`build/work` 等）、実行時ログ、生成scan/jpg、計測結果JSON |
| `Makefile` | **ビルド・検証エントリポイント** | lint、単体、結合、相互運用、性能、拡張試験の実行ターゲット定義 |

---

## 3. 各工程の基本ルール

### 3.1 要件定義（Requirements Definition）ルール
1. **仕様の優先順位**:
   1. `docs/requirements.md`（ユーザー確定要件：最上位）
   2. `docs/blocks/rtl_contract.md`（初回実装のポート・定数・プロトコル契約）
   3. `docs/design_spec.md`（全体仕様・接続・DRAM形式）
   4. `docs/blocks/README.md` および各ブロック仕様
2. **「確定要件」と「設計案」の分離**:
   - `docs/requirements.md` 内で「設計案」と記載された項目は、ユーザー確定要件ではなく提案段階です。
   - 確定要件（例：Verilog-2001、排他動作、256 MHz、A4 100ppm、AXI64bit、65535×65535寸法）はAIエージェントの独断で緩和・変更してはなりません。
3. **仕様矛盾・不整合の処理**:
   - 仕様間の競合や誤りを発見した場合は、勝手にコード側で握りつぶさず、**根拠と変更内容をMarkdownドキュメント（`docs/` 配下）に明記・記録**してから実装・修正してください。

### 3.2 設計仕様作成（Architecture & Detailed Design）ルール
1. **実装契約（`docs/blocks/rtl_contract.md`）の厳格遵守**:
   - ポート名、ビット幅、符号属性（signed/unsigned）、レジスタアドレス、テーブルフォーマットはすべて実装契約に従います。
   - 旧ドキュメントの「未決」「後で決定」項目は、`rtl_contract.md` に記載の具現化値を正とします。
2. **ハンドシェイクとストール契約**:
   - ストリーム接続はすべて `valid`/`ready` によるハンドシェイクを徹底します（`s_valid && s_ready` または `m_valid && m_ready` 成立時のみデータ遷移）。
   - 受信側が ready を落とした（ストールした）場合、送信側は提示中の valid およびデータ内容を変化させてはなりません。
3. **バッファ・パイプライン構造**:
   - 画素RAMおよび段間係数RAMは2面（ピンポンバッファ）構成とし、処理と転送のオーバーラップを実現します。
   - 量子化器は反復除算器ではなく、1係数/cycleスループットの「32段パイプライン復元除算器」を採用しています。
4. **エラーハンドリングと停止（Stop）契約**:
   - エラーコードは `0x0`（正常）〜 `0xA`（10: 入力余剰・パディング不正）の標準エラーコードを厳守します（`rtl/jpeg_defs.vh`）。
   - 停止（stop_request）発生時は、AXIバス上で発行済みのAR/AW/Wトランザクションおよび返却データ（R/B）をすべて安全に回収・解放し、アイドル状態に戻す必要があります。
5. **仕様書の同期更新**:
   - 回路仕様やI/Fを変更・拡張した場合は、必ず `docs/rtl_interfaces.md`, `docs/blocks/rtl_contract.md`, `docs/implementation_status.md` を同時に更新してください。

### 3.3 RTL (Verilog) ソースコード作成ルール
1. **言語標準**:
   - 合成対象コードは **Verilog-2001（IEEE 1364-2001）** に準拠すること。
   - FPGA/ASICベンダー固有のマクロ・IP・プリミティブは直接使用せず、推論可能な同期RAMや標準演算記述を用います。
2. **クロックとリセット**:
   - クロックは単一クロック `clk`。
   - リセットは非同期アクティブロー `rst_n`（クロック立上りエッジで同期的に初期化・動作）。
3. **コーディング規約**:
   - ファイル名とモジュール名を一致させる（例: `jpeg_quant.v` → `module jpeg_quant`）。
   - 共通定数、レジスタアドレス、フィールド定義、エラーコードは `rtl/jpeg_defs.vh` からインクルードし、モジュール内に数値を直接ハードコード（マジックナンバー）しないこと。
   - 変換定数テーブルは `rtl/jpeg_c.vh`、ジグザグ走査テーブルは `rtl/jpeg_zigzag.vh` を共用すること。
4. **厳禁事項（品質アンチパターン）**:
   - **空実装・スタブの禁止**: 実体のない擬似パルス（適当なタイマーでdoneを返すなど）、固定値出力、未接続ポート放置で「実装完了」を装ってはなりません。
   - **ソフトウェアへの責任委譲の禁止**: RTLで担当すべき変換・符号化・除算等をソフトウェアに肩代わりさせてはなりません（ソフトウェアはヘッダ処理・テーブル作成・検証用参照モデルに限定）。

### 3.4 検証・RTLシミュレーション（Verification）ルール
1. **検証環境**:
   - シミュレータは **Questa Sim (`vsim` / `vlog`)** を使用（SystemVerilog テストベンチ）。
2. **検証階層と実行コマンド**:
   - **Strict Lint**: `make lint`
     - `vlog -lint` による構文・未宣言・ビット幅不一致チェック。エラー・警告ゼロを必須とする。
   - **単体テスト**: `make unit`
     - 数値演算（`sim/numeric_top.v`）、ビットストリーム（`rtl/jpeg_bitstream.v`）、FIFO/RAM（`sim/storage_tb.sv`）、DMA（`sim/dma_top.v`）、repack（`sim/width_tb.sv`）、APB（`sim/apb_tb.sv`）の独立検証。
   - **結合・相互運用テスト**: `make integration`, `make interoperability`
     - Python/C++参照モデルとの全係数・全ビット一致検証。
     - 生成されたJPEGおよび復号画像について、外部ライブラリ（Pillow/libjpeg）との相互運用性・PSNR画質検証。
   - **性能・ストレステスト**: `make performance`, `make performance-stress`, `make performance-variable`
     - 2480×3508 A4模擬原稿（`tests/data/a4_planar.bin`）を用いたサイクル数測定。
     - AXI公称128 cycle（500 ns相当）遅延、遅延変動（64〜192 cycle）、AR/AW/W受付停止、圧縮率1:1およびノイズによるJPEG膨張時のストレステスト。
   - **Restart拡張テスト**: `make test-restart`
   - **CLIツールテスト**: `make test-tools`
3. **再現性の担保（乱数シード規約）**:
   - 検証スクリプト・テストベンチにおける疑似乱数シードは、原則として固定値 **`20261005`** を使用し、常に100%再現可能なテストとすること。
4. **結果の記録と報告**:
   - シミュレーション結果、測定サイクル数、未検証項目は、`docs/validation_results.md` および `docs/implementation_status.md` に更新記録すること。

### 3.5 ツール・スクリプト実行（Python / Windows）
- **Questa Sim (`vsim`)**: Questa Altera Starter FPGA Edition-64 (`vsim.exe`) が導入済み（PATH設定済み）。波形確認やVerilogシミュレーションに利用可能。
- **Python実行**: Windowsではストア版エイリアスを避け、**`py -3`** または実体 `C:\Program Files\Python314\python.exe` を使用する（`Makefile` もWindows時は `py -3` を自動適用）。
- **必須パッケージ**: テスト・画像生成用に **`pillow`** が必要（導入済み）。

---

## 4. エージェント作業規範（AI Agent Working Guidelines）

1. **チャット履歴を前提としない自律性**:
   - 会話履歴が途切れた場合でも、`docs/implementation_handoff.md` および `docs/implementation_status.md` を起点に作業を継続すること。
2. **環境確認の徹底**:
   - 作業開始時に利用可能なツール（`vsim`, `vlog`, `py`, `make` 等）の有無を確認すること。
3. **回帰検証の義務**:
   - 変更後は必ず `make lint` や関連テストを実行し、リグレッションがないことを確認すること。
4. **Git・成果物管理**:
   - `build/` 配下はコミット対象外。`tests/data/` の新規データは生成スクリプトとともに残すこと。


