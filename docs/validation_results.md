# 検証結果

測定日: 2026-10-05。最終RTLに対する`make test`、`make performance`、`make performance-stress`、`make performance-variable`はすべて正常終了。

## 単体・結合

[実行ログ](validation/make_test.log)と[外部JPEG相互運用結果](validation/interop.json)を保存した。53,104数値ベクトル、100 bitstream往復、FIFO/RAM、30フレームrepack/unpack、APB、同時read/write DMA、11小画像の固定・変動遅延結合試験、3外部JPEGのRTL復号、11 RTL JPEGの外部復号はPASS。lintはVerilog-2001、ADDR_W=64/ID_W=1と32/2でPASS。

小画像444の外部復号との最大差は0～1、非零誤差のPSNRは54.39～57.00 dB。422/420は外部側chroma upsamplingが異なるため、外部復号の成功のみ評価する。内部のplanar結果は全形式とも整数モデルに一致。

## A4サイクル実測

2480×3508、444、408,270ブロック、26,099,520サンプル、Q=16、seed=20261005。自作のDC12 symbol（length4）、AC162 symbol（length8）テーブルを使用する。模擬原稿の生成条件は[入力条件](../tests/data/a4_conditions.json)、生成コードは[原稿生成](../tools/generate_manuscript.py)。ノイズ条件はテストベンチのseed固定xorshiftで全成分を置き換える。

| 条件 | encode cycle | decode cycle | encode秒@256MHz | decode秒@256MHz | scan byte | 外部復号最大差 | PSNR dB |
|---|---:|---:|---:|---:|---:|---:|---:|
| [模擬原稿・固定128cycle](validation/performance.json) | 82,879,389 | 82,879,350 | 0.323748 | 0.323747 | 3,310,375 | 2 | 63.647 |
| [ノイズ・固定128cycle](validation/performance_stress.json) | 82,879,518 | 82,879,467 | 0.323748 | 0.323748 | 31,193,437 | 2 | 54.535 |
| [模擬原稿・変動64～192cycle](validation/performance_variable.json) | 93,968,886 | 82,879,395 | 0.367066 | 0.323748 | 3,310,375 | 2 | 63.647 |

全条件で153,600,000 cycle/pageのRTL予算内。encodeとdecodeは別ジョブで測定し、両方を行う時間ではない。PSNRは同じscanのRTL復号とPillow/libjpeg直接YCbCr復号の差で、元画像に対する圧縮画質ではない。scan byteはヘッダ・EOIを含まない。

固定応答はAR受付から先頭R提示、最終W成立からB提示まで128 cycle（256 MHz換算500 ns）。変動応答は一様64～192 cycleに独立したAR/AW/W受付停止を加える。同一IDの順序待ち、R/B ready待ちは公称遅延に加算される。公称平均と実際の先頭R handshake遅延平均、FIFO峰値、予約byte、各チャネル受付待ちは各JSONに保存した。

ノイズ出力は入力より大きく、圧縮率1:1を容量上限として扱っていない。別の結合試験で容量超過エラーも検証済み。通常原稿の圧縮比は約7.88、ノイズは約0.84（入力sample byte / scan byte）。

CPU準備・入出力時間は未測定。CPU込み100 ppm、実デバイスの256 MHz成立、画質しきい値の合格は未認定。その他の残課題は[実装状況](implementation_status.md)を参照する。

## Restart拡張後の再測定

上記表は初回実装の結果。Restart拡張後はencoder/decode入力を分離して再測定した。最新の独立入力・RTL実測とJSONは[Restart対応の性能表](restart_decode.md)を参照する。
