# 追加5画像の分離試験

実施日: 2026-10-06。新規の公開画像5枚（PNG 3枚、JPEG 2枚）を取得し、すべての主試験PASS。別の候補JPEG 2枚はRestart付きのため、対応外拒否試験として検証した。

RTLで生成したJPEGをRTLデコーダーに入力していない。PNG→RTL encode→外部Pillow/libjpeg decodeと、公開元JPEG→RTL decode→外部結果比較を分離した。取得した元ファイルにリサイズ・再圧縮は行っていない。

## 画像と結果

| 公開入力 | 寸法 | 処理 | cycle | 結果 |
|---|---|---|---:|---|
| [dice1.png](https://commons.wikimedia.org/wiki/File:PNG_transparency_demonstration_1.png) | 800×600 | encode 444 | 4,568,094 | PASS: 外部復号成功 |
| [dice2.png](https://commons.wikimedia.org/wiki/File:PNG_transparency_demonstration_2.png) | 997×747 | encode 422 | 4,809,267 | PASS: 外部復号成功 |
| [color_circle.png](https://commons.wikimedia.org/wiki/File:Color_circle_(RGB).png) | 2048×2048 | encode 420 | 19,956,300 | PASS: 外部復号成功 |
| [hopper.jpg](https://github.com/python-pillow/Pillow/blob/main/Tests/images/hopper.jpg) | 128×128 | decode 420 | 78,561 | PASS: 整数参照pixel一致・外部比較完了 |
| [testorig.jpg](https://github.com/libjpeg-turbo/libjpeg-turbo/blob/main/testimages/testorig.jpg) | 227×149 | decode 420 | 183,240 | PASS: 整数参照pixel一致・外部比較完了 |

PNGの透過は白背景に合成し、Q=16を使用。997×747では画像・MCUの端数処理も含む。JPEG 2枚は公開プロジェクトが提供するテスト用の元JPEGを、そのままRTLデコーダーへ入力した。

## 画素差

encodeは元PNG（白背景合成後のRGB）と外部復号結果、decodeはRTLツールのRGBとPillow/libjpegのRGBを比較する。

| 入力 | 比較 | 最大差 | 平均絶対差 | MSE | PSNR dB |
|---|---|---:|---:|---:|---:|
| dice1.png | encode | 30 | 1.420392 | 3.968159 | 42.145 |
| dice2.png | encode | 26 | 1.717562 | 5.736137 | 40.545 |
| color_circle.png | encode | 91 | 1.236377 | 4.638619 | 41.467 |
| hopper.jpg | decode | 43 | 2.127238 | 15.735962 | 36.162 |
| testorig.jpg | decode | 34 | 1.587401 | 7.372360 | 39.455 |

encodeの差は非可逆圧縮・色変換・samplingによる損失を含む。decodeの差は固定小数点IDCT・色変換と、RTLツールのnearest-neighbour chroma拡大とlibjpeg補間の違いを含む。PSNRの画質受入しきい値は設定しておらず、PASSは正常完了・寸法一致、decodeの整数参照モデル一致を意味する。

## 対応外の確認

候補として取得した[Cat03.jpg](https://commons.wikimedia.org/wiki/File:Cat03.jpg)（1600×1598）と[Goldfish3.jpg](https://commons.wikimedia.org/wiki/File:Goldfish3.jpg)（784×840）は非zero Restart intervalを持つ。両方とも`restart intervals unsupported`でエラー終了し、PNGを生成しなかった。Baselineへの再圧縮やRestart除去による入力改変は行っていない。

## 保存・再現

- [入力画像・出典](../tests/data/internet_five/README.md)、[URL・SHA-256](../tests/data/internet_five/sources.json)
- [出力画像](../tests/results/internet_five/README.md)、[測定JSON](../tests/results/internet_five/report.json)
- [実行ログ](validation/internet_five.log)、[試験スクリプト](../tools/test_internet_five.py)

```sh
make test-internet-five
```

取得済み入力とhashを使うので再実行にネットワークは不要。JPEG生成と復号は既存RTLのVerilatorシミュレーション。今回RTLと変換ツールの変更は行っていない。PNGの作者・派生画像のライセンス表示は入力・出力READMEを参照する。
