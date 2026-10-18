# Restart decode試験の出力

*_rtl.pngはJPEGをVerilog RTLで復号したもの。*_external.pngは同じJPEGをPillow/libjpegで復号したもの。RTL encoder出力は入力として使用していない。

fmt*/flat/marker*は検証用ソフトウェア参照encoderの生成画像。cat/goldfishは元の公開JPEGをそのまま復号したもの。PNGへの形式変換、整数IDCT/色変換による変更を含む。

cat写真: **Fir0002/Flagstaffotos**。出典 https://commons.wikimedia.org/wiki/File:Cat03.jpg 。元画像とPNG派生画像はGFDL 1.2: https://www.gnu.org/licenses/old-licenses/fdl-1.2.html 。

goldfish写真: Heptagon（Commons表記）、Public domain。出典 https://commons.wikimedia.org/wiki/File:Goldfish3.jpg 。

入力hash/URLは[入力sources.json](../../data/internet_five/sources.json)。測定値はreport.json、仕様・条件は[Restart説明](../../../docs/restart_decode.md)。
