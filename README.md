# JPEG_TOP：Verilog JPEGエンコーダー・デコーダー

Verilog-2001によるBaseline JPEGエンコーダー・デコーダー。YCbCr 4:4:4／4:2:2／4:2:0、APB設定、AXI64bit DMA、Restart付きJPEGのdecodeを実装済み。CPUはヘッダ・色変換・テーブル準備を担当し、RTLはscanデータを処理する。

実装内容・検証結果・残課題は[実装状況](docs/implementation_status.md)、内部I/Fは[RTL接続仕様](docs/rtl_interfaces.md)。継続作業では[実装引き継ぎ](docs/implementation_handoff.md)を読む。

- [要件定義](docs/requirements.md)
- [全体設計・接続図](docs/design_spec.md)
- [ブロック別仕様一覧](docs/blocks/README.md)
- [RTL実装共通仕様](docs/blocks/rtl_contract.md)

## 実行

Questa Sim（vlog/vsim）、Python 3、Pillowが必要。

```sh
make test
make performance
make performance-stress
make performance-variable
```

`rtl/`に本体、`sim/`にテストベンチ、`tools/`に参照モデルと画像生成、`tests/data/`に再生成可能な入力を格納する。結果は`build/`に出力する。

256 MHz換算のRTLサイクル予算と、CPU込み100 ppm・実デバイスのタイミング成立は区別する。後者は未検証。

## PNG/JPEG変換ツール

既存RTLをシミュレーションして画像ファイルを変換できる。

```sh
make jpeg-tools
python3 tools/jpeg_encode.py input.png output.jpg
python3 tools/jpeg_decode.py output.jpg decoded.png
```

設定・対応形式・検証は[ツール説明](docs/jpeg_tools.md)。試験は`make test-tools`。

Restart decodeの仕様と検証は[Restart対応](docs/restart_decode.md)。encodeはRestartを生成しない。
