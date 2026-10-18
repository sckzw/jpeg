# RTLを使うPNG/JPEG変換ツール

更新日: 2026-10-06

PNGをJPEGへエンコードし、JPEGをPNGへデコードするCLI。DCT/IDCT、量子化/逆量子化、Huffman、bitstream処理は既存の`jpeg_top` RTLをQuesta Sim（`vsim`）で実行する。Pillowを圧縮・復号の代替には使わない。PNG入出力、RGB/YCbCr変換、サブサンプリング、JPEGヘッダ処理はCPU側の担当。

## ビルドと実行

プロジェクトルートから実行する。Questa Sim（vsim/vlog）、Python 3、Pillowが必要。

```sh
make jpeg-tools
python3 tools/jpeg_encode.py input.png output.jpg
python3 tools/jpeg_decode.py output.jpg decoded.png
```

統合コマンドも同じ機能を呼び出す。

```sh
python3 tools/jpeg_tool.py encode input.png output.jpg --quant 8 --sampling 420
python3 tools/jpeg_tool.py decode input.jpg output.png
```

既定は`--quant 16 --sampling 444`。quantは全成分・全周波数で共通の量子化値1～255で、小さいほど圧縮損失が減る。一般的なJPEG品質値1～100とは異なる。samplingは444/422/420。透過PNGは白背景へ合成する。入力と同じパスへの出力は拒否する。出力先に既存の別ファイルがあれば上書きする。

エンコードは汎用の固定Huffmanテーブルを使う。最適化Huffmanや標準quality曲線を使用する一般JPEGツールとの圧縮サイズ一致は意図しない。

## 対応するJPEG入力

- 8bit Baseline Sequential、YCbCr 3成分。
- Y/Cb/Crの順に全成分を含む単一scan。
- 4:4:4、4:2:2、4:2:0。8bit量子化テーブル。
- DRI/Restart付きのBaseline decodeに対応。RSTはCPUで除去せずRTLで処理する。encodeはRestartを生成しない。
- scanごとのDCテーブル最大2種類、ACテーブル最大2種類。ファイル内のIDをRTLの0/1へ再配置する。Qは成分別の3面へコピーする。
- APP/COMメタデータは読み飛ばす。Adobe APP14はYCbCr transform=1のみ許可。

Progressive、グレースケール、RGB/CMYK/YCCK JPEG、複数scan、16bit DQT、他のsamplingは対応外で、エラー終了する。ソフトウェアJPEG復号への自動切替はない。EXIF orientationやICC profileの適用・メタデータ保存は行わない。PNG入力はPillowのRGB変換を使う。

復号時のchroma拡大は画素位置に合わせたnearest-neighbourを使うため、libjpegの補間によるRGB結果と異なる場合がある。JPEGは非可逆であり、PNG→JPEG→PNGで元画像との完全一致は期待しない。

## 構成

| ファイル | 役割 |
|---|---|
| `tools/jpeg_encode.py`, `tools/jpeg_decode.py` | 個別CLI入口 |
| `tools/jpeg_tool.py` | PNG入出力、色変換、JPEGヘッダ、ジョブ準備 |
| `tools/jpeg_cpu.py` | 境界・形式・テーブル検査付きBaselineパーサーと検証用scan参照復号 |
| `sim/jpeg_tool_tb.sv` | ファイルベースのジョブ実行（テーブル設定・メモリ展開・RTL実行・出力保存）を行うSystemVerilogテストベンチ |
| `build/work/` | Questa Simコンパイル成果物（`jpeg_tool_tb` 等） |

ジョブは一時ディレクトリに保存し、成功・失敗にかかわらず終了時に削除する。RTLのscanを受け取った後にJPEGファイルを組み立てる。decodeもRTLのplanar画素を回収してからPNGを保存する。異常時は非zero終了コードと理由を表示する。

AXIの公称応答遅延は128cycle、受付停止なし。画像strideを8byteに整列し、JPEGエンコード容量を512byte/block+64byteとして確保する。シミュレータのメモリ領域が1 GiBを超えるジョブは拒否する。これはホスト側ツールの制限であり、RTLの最大寸法とは別。表示サイクル数はジョブ開始から完了検出・結果カウンタ読出しまでで、CPU前後処理やシミュレータの実行時間を含まない。実行速度はソフトウェアJPEGライブラリより遅い。

## 検証

```sh
make test-tools
make test
```

2026-10-06、Questa Simで`make test-tools` PASS。seed=20261006。6 PNG encodeでscan byte一致、9 JPEG decodeで整数参照モデルから生成したRGB pixel一致、外部ライブラリによる生成JPEGの復号、テーブルID/成分ID変更、両CLI入口を確認。Progressive、グレースケール、EOI欠落、DRIとscanの不整合、quant範囲外、同一入出力パスの拒否を確認した。

[CLI実行ログ](validation/jpeg_tools.log)を保存する。共有ドライバとパーサーの変更は既存`make test`でも回帰検証し、全試験PASS。結果は[回帰ログ](validation/jpeg_tools_regression.log)に保存した。RTL自体の変更はないため、A4性能試験の再測定は行っていない。

## 動作例

160×96のRGB勾配・チェック柄を[入力PNG](../tests/data/tool_demo.png)として保存した。

```sh
python3 tools/jpeg_encode.py tests/data/tool_demo.png build/jpeg_demo.jpg --sampling 420 --quant 16
python3 tools/jpeg_decode.py build/jpeg_demo.jpg build/jpeg_demo.png
```

JPEGは1,998byte、RTL scanは1,550byte。encode 73,662cycle、decode 73,671cycle。出力は`build/jpeg_demo.jpg`と`build/jpeg_demo.png`。デモ入力はR=x*255/159、G=y*255/95（整数除算）、Bは16pixel格子の32/224として生成した。

## 公開画像での分離検証

`make test-internet-images`で、公開PNGのRTL encodeと別の公開Baseline JPEGのRTL decodeを分離して再実行できる。RTL encode出力をRTL decoderへ入力しない。取得元・結果は[公開画像試験](internet_image_tests.md)。

## Restart復号の拡張

2026-10-06にdecodeのDRI/RST対応を追加した。JPEG入力のDRIを自動設定するためCLIの追加オプションは不要。[仕様・試験結果](restart_decode.md)、再現は`make test-restart`。
