# Restart対応の仕様変更

2026-10-06のユーザー依頼により、従来の「Restartなし」をデコード側について拡張する。エンコードはRestartを生成しない。有効なBaseline JPEGにRestartは必須ではない。

## 追加契約

- APB 0x06C `RESTART_INTERVAL`: RW、下位16bit、単位MCU、reset=0。上位16bitの非zero書込み、busy中の書込みはPSLVERR。decode start時の設定を使用する。encodeで非zeroならCONFIGエラー。
- CPUがDRIを読み取り、intervalを設定する。scan入力にはRST0～RST7を含める。CPUでマーカーを除去したり、DC予測を代行したりしない。
- entropyがformat別の3/4/6 blockを1 MCUとして数える。interval MCU処理後、最終MCUでなければRestart handshakeを要求する。
- bitstreamはFF00とRSTを区別し、RSTで入力を保持する。entropyが区切りまで消費した後、残り0～7bitが全1であることとRST番号を検査し、reservoirを空にする。
- 正常なRestart handshakeでDC予測値全3成分を0へ戻す。RST番号は0から順に増え、7→0で巡回する。
- 欠落・途中EOF、早過ぎ／遅過ぎ、番号不一致、padding不正、interval=0でのRST、最終MCU後の余計なRSTをエラー扱いする。破損後の再同期・部分画像の救済は実装しない。

基準: [ITU-T T.81](https://www.w3.org/Graphics/JPEG/itu-t81.pdf)のDRI、RST、Restart interval、DC予測リセット、全1padding。旧文書のRestart非対応記述より本拡張を優先する。

## 実装と検証結果

RTLのjpeg_apb/ctrl/top/entropy/bitstream、CPUパーサー、Verilator CLIを拡張した。JPEGデコードCLIの追加引数は不要で、入力DRIを自動設定する。エンコードは従来どおりRestartを生成しない。DRI以外の既存レジスタ配置、Progressiveなどの対応範囲は変えていない。

- lint: Verilog-2001、ADDR_W=64/ID_W=1と32/2でPASS（既存4種類の警告抑制のみ）。
- bitstream: padding長0～7×RST番号0～7の64組、FF00、FF fill、marker保持中のstall、誤番号、不正padding、最終余計RST、FF FF 00の拒否をPASS。
- APB: 0x06C reset/read/write、65535、上位bit拒否、busy write拒否をPASS。
- トップ: ソフトウェア参照encoderが作った29 scanを固定128cycleと変動64～192cycle・受付stallで試験。18正常入力は係数参照から作ったplanar画素・stride sentinelと一致。11異常入力は期待エラー。interval=1/2/3/65535、444/422/420、端数、RST番号巡回、最終intervalちょうどの終了、marker fill、4 KiBをまたぐRSTを含む。marker保持中のCPU stop、DMA回収、再開始、encodeでの非zero interval CONFIG errorもPASS。
- CLI: ソフトウェア製7 JPEGと公開Restart付き2 JPEGを復号し、整数参照RGBと全byte一致。外部Pillow/libjpegとも比較。11異常JPEGの非zero終了と出力なしを確認。RTL encode出力をRTL decoderへ入力していない。
- 既存`make test`と`make test-tools`も回帰実行し、全試験PASS。最新ログは下記に保存した。

公開JPEGの実測:

| 入力 | 寸法 | DRI MCU | sampling | RTL cycle | 外部RGB最大差 | PSNR dB |
|---|---|---:|---|---:|---:|---:|
| [Cat03.jpg](https://commons.wikimedia.org/wiki/File:Cat03.jpg) | 1600×1598 | 200 | 444 | 24,360,570 | 4 | 49.817 |
| [Goldfish3.jpg](https://commons.wikimedia.org/wiki/File:Goldfish3.jpg) | 784×840 | 98 | 444 | 6,267,303 | 4 | 48.165 |

RGB差のPSNRは同じJPEGをRTLツールと外部ライブラリで復号した差で、元の非圧縮画像との画質ではない。444はIDCT/色変換の差を含む。乱数422/420の外部RGB比較はchroma補間差が大きく、PSNR約16～19 dBも含むが、整数モデルのnearest chroma結果とはpixel一致。画質受入しきい値の合否をこの数値だけで判定していない。

[Restart CLI全測定](../tests/results/restart/report.json)、[入力生成](../tools/generate_restart_vectors.py)、[テストベンチ](../sim/top_test.cpp)、[CLI試験](../tools/test_restart_cli.py)、[結果画像](../tests/results/restart/README.md)。

## 再現

```sh
make test
make test-tools
make test-restart
python3 tools/jpeg_decode.py tests/data/internet_five/cat.jpg build/cat.png
python3 tools/jpeg_decode.py tests/data/internet_five/goldfish.jpg build/goldfish.png
```

乱数seed=20261006（Restart入力）、20261005（AXI/bitstream）。Verilator 5.049 devel（v5.048-230-gde0236be2）。入力生成はCPUの検証用参照encoderを使う。製品ツールはDCT/IDCT、量子化、Huffman処理をRTLで実行する。公開写真を再圧縮・marker除去していない。

保存ログ: [lint/単体](validation/restart_unit.log)、[Restart CLI](validation/restart_tests.log)、[最終RTL固定/変動](validation/restart_top.log)、[既存回帰](validation/restart_regression.log)。

破損区間からの救済・再同期、encoderのマーカー生成、実機合成タイミングは未実施。DRIを設定せずにscanだけ与えるとRSTは不正markerとなる。0x06Cをencodeジョブに持ち越さないようCPUは0を設定する。


既存の小画像回帰ではCPU参照scanを入力し直し、CLI回帰ではPillowが別途生成したJPEGを入力するよう変更した。A4 decode性能入力もPillow/libjpegで独立生成する。RTL encoderの出力をRTL decoderへ直接流す経路はこれらの試験から除いた。

## 分離入力でのA4再測定

Restart拡張後、2480×3508・444の性能を独立した入力で再測定した。encoderは既存の自作Q=16/固定Huffman、decoderは外部Pillow/libjpeg製JPEGを使う。通常decoder入力は原稿PNG・Q=16、ノイズdecoder入力はseed=20261005の独立RGB乱数・Q=1。encoderのノイズは従来のYCbCr xorshiftで、decoderとは別の入力。全条件でRTLサイクル予算153,600,000/page以内。CPU準備時間と実256 MHz成立は未検証。

| 条件 | encode cycle | decode cycle | encode秒@256MHz | decode秒@256MHz | encode scan byte | 独立decode scan byte |
|---|---:|---:|---:|---:|---:|---:|
| [通常原稿・固定128cycle](validation/restart_performance.json) | 82,879,389 | 82,879,350 | 0.323748 | 0.323747 | 3,310,375 | 1,844,363 |
| [ノイズ・固定128cycle](validation/restart_performance_stress.json) | 82,879,518 | 82,879,476 | 0.323748 | 0.323748 | 31,193,437 | 35,776,890 |
| [通常原稿・変動64～192cycle](validation/restart_performance_variable.json) | 93,968,886 | 82,879,326 | 0.367066 | 0.323747 | 3,310,375 | 1,844,363 |

encoder JPEGは外部復号で正常性を確認した。decoderの外部画素差は同じ独立入力JPEGから比較し、入力SHA-256、差・PSNR、FIFO/AXI統計は各JSONに保存した。`make performance` / `make performance-stress` / `make performance-variable`ですべて再現できる。
