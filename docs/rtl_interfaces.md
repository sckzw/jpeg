# RTL接続と初回実装の具体化

更新日: 2026-10-05

仕様の優先順位は`implementation_handoff.md`に従う。ポートの正確な一覧は各`rtl/jpeg_*.v`のmodule宣言を参照する。全モジュールは単一clk、同期低有効rst_n。RTL本体はVerilog-2001。

## 外部I/F

`jpeg_top`は`psel/penable/pwrite/paddr[11:0]/pwdata[31:0]`と`prdata/pready/pslverr`、`m_axi_*`のAR/R/AW/W/Bを持つ。ADDR_W=64（32〜64）、ID_W=1（1以上）。AXI64bit、同一ID=0、INCR、LOCK/CACHE/PROT/QOS=0。USER/REGIONは持たない。CPU設定値はbusy中に変更できず、CONTROL.stopだけの書込みではmodeを変更しない。

APB定数は`rtl/jpeg_defs.vh`。INPUT_BYTES/OUTPUT_LIMIT/OUTPUT_BYTES、成分/JPEG baseの上下32bitは仕様通り。FORMAT=0/1/2は444/422/420。TABLE_SELECTは成分ごとにQ ID2bit、DC ID1bit、AC ID1bit。画像base/strideとJPEG baseは8byte整列。

## 内部I/Fと所有権

- DMA read: `req_*`はaddr/len/size/last。lenはAXI beat数-1、0〜15。受付時にbyte容量を予約し、ARを保持する。データ返却はdata64/keep8/last。JPEGの4 KiB・末尾分割、画像の行アドレスと自然整列4/2/1byte分割はトップが生成する。
- DMA write: `req_*`受付後に指定beat数のs_data/s_keepを全て収集し、容量検査後AW/Wを提示する。データを確保してから要求を出す。WはAWと独立。1バーストの送信中にも以前のBを回収する。JPEG writeはFIFOに最大128byteを集め、16 beat、4 KiB境界、最後の短縮要求を発行する。画像writeは1 beat。
- stream FIFO: word側はdata64/keep8/last。最終wordのkeepは下位連続。`jpeg_unpack/jpeg_pack`がbyte列と変換する。unpackは最後のbyteを消費するまでFIFOのwordを保持する。FIFO単体はword転送ごとにbyte使用量を更新する。
- block RAM: reserve→64書込み→FULL→同期read_req/応答→最終応答消費でFREE。`jpeg_block_stream`が2面を交互に管理し、別面のfill/readを並行する。画素RAMの物理所有はトップにある。DMA側に同じRAMを複製しない。
- transform/quant/entropy: 32bit係数（transform encode入力は0〜255）、index6、component2、block_seq32、last_block。入力・出力のindex63成立でブロック終了。自然順とzigzagの変換はquantized係数RAMだけで行う。
- bitstream: tokenは右詰めbits32/nbits6。finishハンドシェイクでパディング/stuffingと最終byte lastを確定。decodeはpeek16/available5/eofとconsumeハンドシェイクを用いる。

モード間で同じ3組の2面RAM、変換器、量子化器、符号処理器、FIFOを使う。DCT/IDCTは8乗算器・加算木3段・丸め1段の共有2パス。入力配列も2面で、次ブロックの入力を演算と重ねる。量子化は表参照1段+復元除算32段+丸め1段。逆量子化も同じメタデータパイプラインを通す。演算範囲異常の出力は転送しない。

## テーブル実装

`jpeg_tables`に3 Q、ENC DC/AC各2、DEC DC/AC各2のメモリ、loaded bitmap、validを置く。これはAPBと演算器を結ぶ追加ブロックであり、CPUへの符号処理委譲ではない。

量子化64、encode Huffman256、decode Huffman320要素をCPUが書く。commitはkind/idをラッチし、1要素/cycleで全loadedと値を検査して待ち状態を返す。decodeはcanonical連続性、min/max/count、先頭symbol、過剰割当、全1符号、カテゴリを検査する。commitにはTABLE_ADDR.indexを使用しない（全要素ロード後にindexが範囲外でもcommit可能）。valid対象の最初の再書込みでbitmapを新ロードとしてクリアする。

内部RAM readの表出力は組合せ、quant入口とentropy lookupでレジスタ化する。decodeの16長比較には16範囲を並列供給する。実装デバイスに合わせたメモリ推論/配置は合成評価の課題。

## 停止と完了

最初のエラーを保持する。同cycleはread、write、config、table、input（padding含む）、entropy、capacity、numeric、CPU stopの順。APB単独の不正アクセスはジョブ停止にしない。

stop/errorは新規要求を止め、提示済みAR/AW/Wを撤回しない。Rは破棄経路で、Wは全予約データを送り、Bを全回収する。両DMA idle後に内部clearする。STATUS.error W1CはDMA idle限定で、errorが立っていない場合は処理中でも内部clearを起こさない。OUTPUT_BYTESは内部clearで消さず、次startで0にする。

全体doneはread_done、write_done、transform/quant/entropy/bitstreamのdoneとdecode画素の最終出力消費を確認する。最後のW送信だけでdoneにしない。

## 短いAXI読出しの再パック

JPEG末尾の4/2/1byte要求をそのままFIFOへ置くと、最終word以外にも短いkeepが出る。`jpeg_input_fifo`は`jpeg_repack`でこれらを8byte単位にまとめ、最後だけ短いkeepにする。画像の端処理も同じbyte順で再パックする（各ブロックの有効読出し量は8行×行幅で8byteの倍数）。64bit全keepで蓄積がない場合は直結して余分な遅延を加えない。DMAに返すused_bytesには再パック中のbyteも含め、used+reserved<=2048の予約規則を維持する。

## 境界の補足

逆量子化のQは41bit正値にゼロ拡張し、係数も41bitへ符号拡張して乗算する。積は40bitに収まることを数値範囲から確認し、その後32bit範囲を検査する。

decode tableの累積symbol数が256に達した後のcount=0の長さは、8bit first_symbolで256を表せない。この場合first_symbol=0を許容し、first_symbolと累積位置の一致はcount>0だけで検査する。count=0ではmin/max/firstを符号照合に使用しない。全要素の上位予約bit検査とcanonical累積は維持する。

OUTPUT_BYTESを次のAPBアクセスから0にするため、write DMAの初期化にはAPB開始パルスも使用する。開始はIDLEだけで受けるため、既発行AXIを初期化で破棄しない。設定不正で開始が拒否されたジョブも書込み量は0となる。実際の処理段・DMA要求開始はctrlの検査後のstartで行う。

## Restart decode拡張（2026-10-06）

APB 0x06C RESTART_INTERVAL下位16bitでMCU間隔を設定する。encodeは0のみ。entropyはformatとintervalを入力し、restart_valid/restart_expectedをbitstreamへ出力する。bitstreamはrestart_pending（区間末尾到達）、restart_ready（padding・番号検査済みack）を返す。entropyはackでDC予測全成分をresetする。segment_endをHuffman短尾処理にも使う。RSTは入力scanに残したまま供給する。詳細は[Restart契約](restart_decode.md)。
