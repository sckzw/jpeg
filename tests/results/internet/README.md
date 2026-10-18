# 分離試験の出力

encoded_*.jpgは公開Example.pngをRTLで圧縮したもの。encoded_*_external.pngはそれをPillow/libjpegで復号したもの。このJPEGをRTLデコーダーへ入力していない。

flower_rtl.pngとflower_external.pngは公開Baseline JPEGをそれぞれRTL／Pillow/libjpegで復号したもの。元写真はDavid Crawshaw、CC BY-SA 3.0。PNGへの変換と復号処理による変更を含み、これらの花画像にも同じライセンスを適用する。
出典: https://commons.wikimedia.org/wiki/File:JPEG_example_flower.jpg
ライセンス: https://creativecommons.org/licenses/by-sa/3.0/

測定値はreport.json、条件と解釈は[説明](../../../docs/internet_image_tests.md)。
