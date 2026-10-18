# RTL実装状況

更新日: 2026-10-05

## 完了範囲

既存要件と`blocks/rtl_contract.md`に基づき、Verilog-2001 RTL、整数参照モデル、単体・結合・性能検証環境を実装した。処理を省略したstubはない。CPU担当はJPEGヘッダ、色変換、サブサンプリング、テーブル準備。RTLはBaseline、8bit YCbCr、444/422/420、単一scanの圧縮・復号を排他的に実行する。encodeはRestartなし、decodeは2026-10-06の拡張でDRI/RSTに対応する。

| RTL | 実装内容 |
|---|---|
| `jpeg_top.v` | 成分・MCU・端処理、段間接続、APB/AXI外部ポート |
| `jpeg_apb.v`, `jpeg_ctrl.v` | 設定、開始・停止、64bitカウンタ読出しスナップショット、W1C、設定検査、完了・エラー |
| `jpeg_tables.v` | Q 3面、ENC/DEC DC/AC各2面、全要素ロードbitmap、commit・canonical検査 |
| `jpeg_dma_read.v`, `jpeg_dma_write.v` | AXI64bit、同一ID、各最大8 outstanding、応答検査、提示済み要求維持と停止後回収 |
| `jpeg_stream_fifo.v`, `jpeg_repack.v`, `jpeg_input_fifo.v` | 2048byte FIFO、keep/last、端数再パック、最終バイト消費までの所有保持 |
| `jpeg_block_ram.v`, `jpeg_block_stream.v` | 2面64要素RAM、同期読出し、ready/valid保持、自然順・zigzag、面間重畳 |
| `jpeg_transform.v` | DCT/IDCT共有8乗算器、Q14定数、2pass、5段演算、入力2面、丸め・範囲検査 |
| `jpeg_quant.v` | 34段量子化パイプライン、global stall、逆量子化、Q零・数値範囲検査 |
| `jpeg_entropy.v`, `jpeg_bitstream.v` | DC差分、AC run/ZRL/EOB、canonical Huffman、追加bit、FF00、padding、EOF検査 |
| `jpeg_defs.vh`, `jpeg_c.vh`, `jpeg_zigzag.vh` | レジスタ・エラー定数と生成ROM |

ADDR_Wは既定64（32～64）、ID_Wは既定1、係数32bit、同期低有効reset。JPEG burstは最大16 beatsかつ4 KiB境界内。画像の端はencodeでクランプ、decodeで有効画素だけ書き込む。段間2面RAMと変換入力2面を使い、ブロック処理を重畳する。

詳細なポート、内部データ経路、仕様の具体化は[RTL接続仕様](rtl_interfaces.md)に記録した。DECテーブルの空lengthで累積symbol位置が256になる場合は8bitの0を格納し、count=0ではfirst_symbol照合を行わない。仕様上表現できない値の扱いも同文書に記録している。

## 検証

`make test`はPASS。Verilog-2001のstrict lintを既定幅とADDR_W=32/ID_W=2で実行し、幅警告を抑制していない。数値53,104ベクトル、bitstream 100往復、FIFO/RAM、30フレームの端数処理、APB、同時read/write DMAを検証した。

11種類の小画像でRTL encode scanを整数参照モデルとbyte一致、decodeをpixel一致で確認した。444/422/420、1×1、MCU端、Q=1/255、密なAC、stride、4 KiB跨ぎを含む。3種類のPillow製JPEGをRTLで復号し、RTL製11 JPEGをPillow/libjpegで復号した。固定遅延と変動遅延の両方で結合試験を実行した。

設定エラー、不完全table commit、256 symbolテーブル、all-one code拒否、容量超過、入力不足・余剰、FF marker、RRESP/BRESP、提示済みAR/AW/W中のstop、回収・連続ジョブを確認した。65535×65535は設定・計数を開始直後の停止で確認した。

実測値と保存ログは[検証結果](validation_results.md)を参照する。

## 再現コマンド・環境

```sh
make test
make performance
make performance-stress
make performance-variable
```

Verilator 5.049 devel（v5.048-230-gde0236be2）、g++ 13.3.0、Python 3.12.3、Pillow 10.2.0。乱数seedは20261005。Makefileはccacheを無効化する。生成入力は`tests/data/`、実行成果物は`build/`。`make clean`はbuildのみ削除する。ROM再生成は`python3 tools/generate_rtl_tables.py`、lintで生成内容を照合する。

## 未検証・残課題

- 対象デバイス未指定。合成・配置配線、面積、実タイミング256 MHzは未検証。Verilatorのサイクル換算はタイミング保証ではない。
- CPUのヘッダ・色変換・tableロード・入出力時間は未測定。CPU込み100 ppmの達成は未認定。
- 外部ライブラリとの画素差・PSNRは測定値であり、画質の最終受入しきい値は未決。報告PSNRは同じscanをRTLと外部ライブラリで復号した差であり、元画像との非可逆圧縮画質ではない。
- 最大寸法全画像の処理、全テーブル・全入力の網羅証明、formal検証、実機AXI相互接続は未実施。
- 模擬原稿は独自生成の文字・表・グラフ・色テクスチャ。HP/Brotherサムネイル画像自体は取得・閲覧していない。
- CPUのJPEGパーサーはBaseline・YCbCr 3成分・単一scan・フレーム順に限定。非標準テーブルIDの再配置にも対応する。汎用JPEGソフトウェアとしての対応は本実装の範囲外。

## 2026-10-06: ファイル変換ツール追加

既存RTLを使うPNG→JPEG／JPEG→PNG CLIを追加した。使用方法・対応範囲・試験結果は[ツール説明](jpeg_tools.md)。`make jpeg-tools`でビルドし、`make test-tools`で独立した整数モデルと照合する。結合試験のAPB/AXIモデルを`sim/jpeg_sim_bus.h`へ共通化し、JPEGパーサーのテーブルID処理と入力検査を拡張した。RTL本体は変更していない。

## 2026-10-06: 公開画像の分離試験

[インターネット画像試験](internet_image_tests.md)を追加。公開PNGをRTL encode→外部decode、別の公開Baseline JPEGをRTL decode→外部結果比較の2系統でPASS。RTL encode出力はRTL decoderへ入力していない。画像、取得元、hash、再現スクリプト、測定値・ログを保存した。

## 2026-10-06: 公開画像5枚の追加試験

新規PNG 3枚と公開元JPEG 2枚を使う[追加分離試験](internet_five_tests.md)を実施し、主試験5枚すべてPASS。PNGは444/422/420を分担し、JPEGは独立したRTL decodeで整数参照pixel一致と外部比較を確認。候補のRestart付きJPEG 2枚は拒否を確認。元画像・hash・出力・ログ・再現スクリプトを保存した。

## 2026-10-06: Restart decode対応

ユーザー依頼に従い、[Restart decode契約](restart_decode.md)を追加した。APB 0x06CのMCU間隔、RST0～7とpadding検査、entropyのMCU計数・DC予測リセットをRTLに実装し、CPUパーサーと画像CLIからDRI/RSTを渡す。encodeはマーカーなしを維持する。正常/異常・stall・停止回収と、公開猫・金魚JPEGの復号を検証。従来の「Restart付き画像の拒否」は拡張前の結果であり、現在は正常復号できる。

Restart拡張後のA4性能を独立した外部JPEG入力で再測定した。通常、膨張JPEG、変動遅延の3条件すべて153,600,000 cycle/page以内。最新の数値・入力条件・ログは[Restart対応の性能表](restart_decode.md)に保存した。古い回帰のdecode入力もCPU参照scan／外部JPEGへ切り替え、RTL encode結果を直接入力しない構成でPASS。

## 2026-10-18: CLIツール・外部画像テストのQuesta Sim (vsim) 移行

Verilator依存となっていた画像変換CLI（`jpeg_tools.md`）および外部画像試験（`make test-internet-images`, `make test-internet-five`, `make test-tools`, `make test-restart`）を、プロジェクト標準のQuesta Sim（`vsim` / `vlog`）環境へ移行した。
- `sim/jpeg_tool_tb.sv` を新規作成: `tools/jpeg_rtl.cpp` で実行していたファイルベースのジョブ構成（`config.txt`, Q/Huffmanテーブルロード, メモリ展開, レジスタ設定, ジョブ実行・完了待機, 出力バイナリ保存）をSystemVerilogで完全再現。
- `Makefile`: `jpeg-tools` ターゲットを `$(WORK)/_tool_built`（`vlog` による `sim/jpeg_tool_tb.sv` ビルド）に切り替え。
- `tools/jpeg_tool.py`: `run_rtl` の呼び出し先をVerilatorバイナリから `vsim -c -lib ... jpeg_tool_tb` に更新。Windowsパスのフォワードスラッシュ統一およびPythonスクリプト内のUTF-8エンコーディング指定を追加。
- 回帰確認: `make lint`, `make test-tools`, `make test-internet-images`, `make test-internet-five`, `make test-restart` がすべてPASSすることを確認。
