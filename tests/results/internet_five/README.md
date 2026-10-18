# 追加の公開画像試験出力

入力元・帰属・ライセンス参照は[入力README](../../data/internet_five/README.md)。元画像のSHA-256は入力sources.jsonに保存。

- dice1_encoded.jpg/dice2_encoded.jpg/color_circle_encoded.jpg: 透過PNGを白背景へ合成し、RGB→YCbCr変換・指定sampling・Q=16でRTL圧縮したもの。
- 上記に対応する*_external.png: 生成JPEGをPillow/libjpegで復号したもの。生成JPEGをRTLデコーダーに入力していない。
- hopper_rtl.png/testorig_rtl.png: 公開元JPEGをRTL復号したもの。
- hopper_external.png/testorig_external.png: 同じ公開元JPEGをPillow/libjpegで復号したもの。

dice1/dice2の派生画像はCC BY-SA 3.0、color_circleの派生画像はCC BY-SA 4.0として扱う。元ファイルからの変更は上記の背景合成、色変換、圧縮・復号、ファイル形式変換。作者とライセンスURLは入力READMEを参照する。

report.jsonに測定結果を保存する。
