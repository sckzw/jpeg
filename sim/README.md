# 検証環境 (Questa Sim / SystemVerilog)

本シミュレーション環境は **Questa Sim (`vlog` / `vsim`)** および **SystemVerilog** で構成されています。
GnuWin32 の `make` コマンド、または `vlog` / `vsim` コマンドラインから実行可能です。

---

## 1. テスト実行コマンド概要

- `make lint`: RTLコードのテーブル整合性検査および Questa Sim (`vlog -lint`) による構文・セマンティクスチェック。
- `make unit`: 各単体テストベンチの一括実行（約50秒）。
  - `numeric_tb`: DCT/IDCTおよび量子化/逆量子化の単体検証（53,104係数/サンプル比較）。
  - `bitstream_tb`: ビットストリーム符号化/復号、64通りのRestart marker・パディング・FF00 stuffing検査。
  - `dma_tb`: 32 bursts × 16 beats リード/ライト、4 KiB境界跨ぎ、最大8 outstanding、128/512 cycle遅延検証。
  - `storage_tb`: ストリームFIFO（wrap/full/keep/last）および2面係数RAM（zigzag走査往復）の単体検証。
  - `width_tb`: 入力FIFOおよびrepack/unpackのバイト整列・端数keep検証。
  - `apb_tb`: APBスレーブのレジスタR/W、スナップショットロールオーバー、パルス生成、テーブルアクセス検証。
- `make integration`: トップレベル結合テスト（約40秒）。
  - 通常遅延モード（公称128 cycle遅延）での11画像ベクタ、非アラインメント、外部画像、エラー・停止/回収検証。
  - 遅延変動モード (`+variable`: 64〜192 cycle一様乱数遅延、受付停止)。
- `make interoperability`: 結合テスト実行後、RTL生成scanデータとPillow/libjpegによる外部復号・画質一致検証（約50秒）。
- `make test`: `lint` → `unit` → `interoperability` の回帰テストを一括実行（約1分40秒）。
- `make test-restart`: ソフトウェア参照エンコーダー生成のRestart入力によるMCU計数・巡回・パディング・エラー耐性検証（約1分20秒）。
- `make clean`: 一時ライブラリ (`build/work`)、実行ログ、波形ファイルを削除。

### 【注意】シミュレーション時間が長大なターゲット
- `make performance`: 2480×3508 画素（408,270ブロック、数千万サイクル）のA4模擬原稿を用いた処理時間測定。
  - **所要時間見込み: 1ケースあたり約 15〜30 分**
  - `make performance-stress` (ノイズ膨張原稿), `make performance-variable` (遅延変動原稿) も同様に長時間となります。

---

## 2. バスモデルと検証方針

### APBバスモデル
- `top_tb.sv` 内のAPBタスク (`apb_wr`, `apb_rd`) により、setup → access の2フェーズプロトコル、commit完了待ち、エラー応答（PSLVERR）を忠実にエミュレーションします。

### AXI4メモリモデル
- 64-bitデータ幅、同一IDで最大8 outstandingの順序維持返却を模擬。
- AR成立から先頭R成立まで、および最終W成立からB成立まで公称128 cycle（500 ns換算）の遅延を適用。
- 遅延変動モード (`+variable`) では、乱数シード `20261005` に基づき 64〜192 cycle の一様乱数遅延および不定期な AR/AW/W 受付停止を与え、ストール耐性を検査します。

### 乱数シード規約
- すべてのテストベンチ・スクリプトで疑似乱数シードを **`20261005`** に固定し、100%再現可能なテストとなっています。

---

## 3. テストベンチ構成一覧

| ファイル | 対象モジュール / 機能 | 検証内容 |
|---|---|---|
| `sim/numeric_tb.sv` | `jpeg_quant`, `jpeg_transform` | 53,104 個の DCT/IDCT・量子化ベクタ突合 |
| `sim/bitstream_tb.sv` | `jpeg_bitstream` | 100組トークン往復、Restart marker・パディング・FF00 |
| `sim/dma_tb.sv` | `jpeg_dma_read`, `jpeg_dma_write` | 32 burstリード/ライト、4KB境界、レイテンシ128/512 |
| `sim/storage_tb.sv` | `jpeg_stream_fifo`, `jpeg_block_ram` | FIFO使用量/last保持、RAM両面/zigzag走査 |
| `sim/width_tb.sv` | `jpeg_input_fifo`, `jpeg_unpack`, `jpeg_repack` | 30フレーム unpack/repack、端数keep整合 |
| `sim/apb_tb.sv` | `jpeg_apb` | APBレジスタR/W、テーブルアクセス、W1Cパルス |
| `sim/top_tb.sv` | `jpeg_top` | トップ結合・遅延変動・Restart拡張・A4性能測定 |
