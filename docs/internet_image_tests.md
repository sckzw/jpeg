# インターネット画像による分離試験

実施日: 2026-10-06。全試験PASS。ユーザー指定に従い、この試験ではRTLエンコードしたJPEGをRTLデコーダーへ入力していない。

## 入力と構成

1. エンコーダー: Wikimedia Commonsの[Example.png](https://commons.wikimedia.org/wiki/File:Example.png)、172×178、palette PNGをそのまま入力。RTL encodeを444/422/420、Q=16で実行し、各出力を独立したPillow/libjpegで復号した。
2. デコーダー: Wikimedia Commonsの[JPEG example flower.jpg](https://commons.wikimedia.org/wiki/File:JPEG_example_flower.jpg)の[旧版元ファイル](https://upload.wikimedia.org/wikipedia/commons/archive/3/3f/20170304154030%21JPEG_example_flower.jpg)、500×477、Baseline 420をダウンロード時のbyte列のまま入力。RTLでPNGへ復号し、独立したPillow/libjpegのRGB出力と比較した。
3. 花JPEGの現行元ファイルはProgressiveだったため、Baselineへ変換せず、対応外として拒否することを確認した。

入力ファイル、URL、SHA-256、サイズ、作者・ライセンスは[sources.json](../tests/data/internet/sources.json)に保存した。取得後のリサイズ・再圧縮は行っていない。エンコード結果のRTL decodeによる往復試験は行っていない。

## エンコーダー結果

PSNRと差は「元PNGのRGB」と「RTL生成JPEGを外部ライブラリで復号したRGB」を比較する。量子化・色変換・subsampling・外部chroma補間の損失を含む。

| sampling | cycle | JPEG byte | scan byte | RGB最大差 | RGB平均絶対差 | PSNR dB |
|---|---:|---:|---:|---:|---:|---:|
| 444 | 308,757 | 17,575 | 17,127 | 37 | 2.580 | 35.988 |
| 422 | 206,034 | 13,080 | 12,632 | 101 | 4.255 | 28.400 |
| 420 | 161,367 | 11,135 | 10,687 | 127 | 5.515 | 26.263 |

全出力は外部ライブラリが正常に復号し、寸法一致。生成JPEGと外部復号PNGは[tests/results/internet](../tests/results/internet/)に保存した。

## デコーダー結果

Baseline 420のRTL decodeは1,169,856cycle、有効sample出力358,000byte。独立した整数参照モデルから生成したRGBと全byte一致。外部Pillow/libjpegのRGB結果との最大差は37、平均絶対差0.775079、MSE 3.766212、PSNR 42.372 dB。

比較画像: [RTL復号PNG](../tests/results/internet/flower_rtl.png)、[外部復号PNG](../tests/results/internet/flower_external.png)。RGB差には固定小数点IDCT・色変換と、RTLツール側nearest-neighbour chroma拡大とlibjpeg補間の違いを含む。差をすべてRTLの演算誤差と解釈しない。画質受入しきい値の合否は判定していない。

Progressiveの現行版は`unsupported JPEG marker 0xc2 (baseline only)`で非zero終了し、出力PNGを作成しなかった。

## 再現

取得済みファイルを使うため、再実行にネットワークは不要。

```sh
make test-internet-images
```

[試験スクリプト](../tools/test_internet_images.py)、[実行ログ](validation/internet_images.log)、[全測定JSON](../tests/results/internet/report.json)を保存した。入力SHA-256は再実行時に照合する。既存のRTLと変換ツールは修正していない。

## 画像の出典・ライセンス

Example.png: Wolfgang / W.、Public domain。花写真: David Crawshaw、[CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/)。元ファイルの出典は上記Commonsページ。花の復号PNGは元写真をJPEGからPNGへ変換したもの（RTL版は固定小数点復号とnearest chroma拡大、外部版はlibjpeg復号）で、同じCC BY-SA 3.0として扱う。これは画像ファイルへの表示であり、RTLやツール全体のライセンス変更ではない。

## 追加試験

新規の5枚を使った結果は[追加5画像の分離試験](internet_five_tests.md)。再実行は`make test-internet-five`。
