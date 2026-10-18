# RTL実装共通仕様

更新日：2026-10-05  
状態：初回RTL実装に用いる設計選択  
参照：[全体仕様](../design_spec.md)、[ブロック一覧](README.md)

既存のブロック仕様だけでは、幅・レジスタ・テーブル形式・演算方式が未確定でRTL実装に不足していた。本書で初回実装の仕様を具体化する。ユーザー確定の要件は変更せず、追加の設計選択は参照モデルと性能評価で検証する。旧文書の「後で決定」に対応する実装値は本書を優先する。

## 1. 言語・パラメータ・対応範囲

- 合成対象はVerilog-2001。テストベンチはSystemVerilogまたはVerilatorのC++を利用可能とする。RAMは推論可能な同期配列、演算定数は固定整数、ベンダーIPは使用しない。
- clk、rst_nは全モジュール共通。rst_n=0をクロック立上りで検出して初期化する。mode=0 encode、1 decode。
- 初回RTLは4:4:4／4:2:2／4:2:0、成分順Y→Cb→Cr、単一インターリーブscan。encodeはRestartなし。2026-10-06のユーザー依頼によりdecodeはDRI/RSTに対応する（[拡張契約](../restart_decode.md)）。CPUがDRIを読み、0x06Cへ設定し、RSTを含むscanを入力する。異なるscan順・非対応形式は開始前に拒否する。

| パラメータ | 実装値・許容範囲 |
|---|---|
| AXI_DATA_W | 64固定 |
| ADDR_W | 初期値64、32〜64。ベース設定レジスタは常に64bit |
| ID_W | 初期値1、1以上。ARID／AWIDは全0 |
| COEF_W | 32固定、2の補数 |
| FIFO_DEPTH | 256エントリ×64bit、入力・出力それぞれ |
| READ_OUTSTANDING／WRITE_OUTSTANDING | 各8固定 |
| Q_TABLES | 3（ID 0〜2） |
| H_TABLES | DC2・AC2（ID 0〜1） |

ARBURST／AWBURST=INCR、ARLOCK／AWLOCK=0、ARCACHE／AWCACHE=0、ARPROT／AWPROT=0、ARQOS／AWQOS=0。USER／REGIONは初回ポートに設けない。接続先で必要ならトップで固定接続する。ADDR_Wより上位のベースアドレスが非ゼロなら開始を拒否する。

## 2. ブロック間ポート契約

表中のs_*はモジュール入力、m_*は出力。s_readyは出力、m_readyは入力。すべてvalid/ready成立時だけ更新する。

| 接続 | ペイロード |
|---|---|
| DMA read→入力FIFO、出力FIFO→DMA write | data[63:0]、keep[7:0]、last |
| FIFOのバイト側↔bitstream | byte[7:0]、last |
| 画素ブロック／transform | sample[7:0]、index[5:0]、component[1:0]、block_seq[31:0]、last_block |
| transform／RAM／quant／entropyの係数側 | coef signed[31:0]、index[5:0]、component[1:0]、block_seq[31:0]、last_block |
| entropy encode→bitstream | bits[31:0]（右詰め）、nbits[5:0]（1〜27） |
| bitstream decode→entropy | peek_bits[15:0]（先頭bitはbit15）、available[4:0]（0〜16）、input_eof |
| entropy decode→bitstream | consume_valid、consume_ready、consume_nbits[4:0]（1〜16） |

byteストリームと符号トークンにはs_valid/s_readyまたはm_valid/m_readyを付ける。decodeのpeekは観測値で、consume成立が消費操作となる。consumeはavailable以下だけ許可する。追加ビットもpeek/consumeで読む。末尾16bit未満の場合、存在する長さのコードだけを照合し、16bitになるまで無条件に待たない。

画素と係数のindex=0で記述子を確定し、同一ブロックの64要素に同じcomponent/block_seq/last_blockを付ける。last_blockは最後のブロックの全要素で1。最終index=63成立でブロック転送完了。自然順index=row×8+col、entropy側だけzigzag indexとする。

制御から各段へstart、mode、stop_request、clearを送る。各段はactive、done、error_valid、error_code[7:0]を返す。doneはジョブ開始で0、担当処理と出力転送完了で1を保持。clearはDMA read/writeのidle後だけ送る。start/clearは1 cycleパルス。stop_requestは回収完了まで保持する。

FIFOはused_bytes[11:0]、DMA readはreserved_bytes[10:0]を保持する。used+reserved<=2048を必ず満たす。RAMの要求・応答にもvalid/readyを付け、read_req(index,bank)に対する応答は最短1 cycle後。応答が停止したらRAM読出し結果を保持し、次要求を止める。

## 3. APBレジスタの具体化

APBアドレス12bit、データ32bit、PSTRBは使用しない（32bit全体書込み）。APB access成立はPSEL&&PENABLE&&PREADY。未実装・4byte非整列・禁止書込みはPSLVERR=1で副作用なし。

| アドレス | レジスタ | 属性・ビット |
|---|---|---|
| 0x000 | CONTROL | RW mode[1]、W1 start[0]／stop[2]。startとstop同時は拒否 |
| 0x004 | STATUS | RO busy[0]／dma_idle[3]、W1C done[1]／error[2] |
| 0x008 | IMAGE_SIZE | RW 幅[15:0]、高さ[31:16] |
| 0x00C | FORMAT | RW 0=444、1=422、2=420、3=不正、bits[1:0] |
| 0x010／0x028 | INPUT_BYTES LO／HI | RW 64bit、JPEG入力長または画像有効サンプル数 |
| 0x014／0x02C | OUTPUT_LIMIT LO／HI | RW 64bit、JPEG出力容量または有効画像書込み量上限 |
| 0x018／0x030 | OUTPUT_BYTES LO／HI | RO 64bit、有効W byte数 |
| 0x01C | ERROR_CODE | RO 最初のジョブエラー、bits[7:0] |
| 0x020 | TABLE_ADDR | RW 下記のテーブルアクセス指定 |
| 0x024 | TABLE_DATA | RW 選択要素。成功転送後にindexを+1 |
| 0x034 | TABLE_COMMIT | WO bit0=commit、対象はTABLE_ADDRのkind/id |
| 0x038 | TABLE_VALID | RO 下記の有効状態 |
| 0x03C | TABLE_SELECT | RW 成分ごとのテーブル選択 |
| 0x040／0x044 | Y_BASE LO／HI | RW 64bit、encode入力／decode出力 |
| 0x048／0x04C | CB_BASE LO／HI | RW 64bit |
| 0x050／0x054 | CR_BASE LO／HI | RW 64bit |
| 0x058／0x05C | JPEG_BASE LO／HI | RW 64bit、encode出力／decode入力 |
| 0x060／0x064／0x068 | Y／CB／CR_STRIDE | RW 各32bit、単位byte |
| 0x06C | RESTART_INTERVAL | RW 下位16bit、decodeのMCU間隔、既定0。上位16bit非zeroとbusy中writeはPSLVERR。encode非zeroはCONFIG error |

設定は停止中だけ書込み可。CONTROL.stop、状態読出し、doneのW1Cはbusy中も可。設定値はリセット0。STATUS.errorのW1CはDMA idle時だけ許可し、ERRORからIDLEへ戻す。busy中のstopは停止エラーを記録し、回収後に再初期化する。停止中のstopは内部clearと全テーブルvalid解除を行う。ジョブ途中のclearは行わない。

OUTPUT_BYTESのLO読出し成立時に全64bitをスナップショットし、HIはその値を返す。CPUはLO→HIの順で読む。startでスナップショットを0にする。INPUT_BYTES／OUTPUT_LIMITはstartで上下をまとめて確定する。

TABLE_ADDR：[11:0] index、[13:12] id、[16:14] kind、他0。kindは0=量子化、1=encode DC、2=encode AC、3=decode DC、4=decode AC。DATA読書きのindex上限超過は拒否し、最後の要素後はindexが範囲外になるため次アクセスを拒否する。

TABLE_VALID：bit0〜2=Q0〜2、bit3〜4=ENC_DC0〜1、bit5〜6=ENC_AC0〜1、bit7〜8=DEC_DC0〜1、bit9〜10=DEC_AC0〜1。

TABLE_SELECTは1成分4bit：下位2bit=Q ID、次1bit=DC ID、次1bit=AC ID。Yは[3:0]、Cbは[7:4]、Crは[11:8]。選択範囲・modeに応じたvalidをstart時に検査する。

## 4. テーブル要素とロード手順

量子化：index0〜63、DATA[7:0]=1〜255、上位0。自然順。全64要素書込み済みをロードビットマップで検査してcommitする。

encode Huffman：index0〜255、DATA[15:0]=code、[20:16]=length、[21]=entry_valid。他0。初回または再ロード時は全256位置を書き、使用しないsymbolは0で設定する。commitは全位置書込み済み・有効符号長1〜16・右詰め符号を確認する。存在しないsymbolをencodeで参照したらエラー。

decode Huffman：index0〜319の32bit要素。長さl=1〜16について、index=4*(l-1)+0:min_code[15:0]、+1:max_code[15:0]、+2:first_symbol[7:0]、+3:count[8:0]。index64〜319はsymbol[7:0]。count=0の長さはコード一致対象から外す。CPUは全320位置をロードする。commitはmin/max/countの整合、symbol範囲、長さ間のcanonical連続性、符号の過剰割当・全1コード禁止・DC/AC symbolの範囲を検査する。検査中はAPB commitを待ち状態とし、失敗はPSLVERRを返してvalid=0。

すべてのテーブルはDATA書込み開始で対象validを0にする。ロード済みビットはcommit成功まで保持し、成功後の最初の再書込みで新ロードとして全ビットをクリアする。RAM本体はリセットで一括クリアせず、valid・ビットマップを0にする。CPUはstart前に必要テーブルをロードする。

## 5. 数値演算と変換器

COEF_W=32。量子化前／逆量子化後のRAMは2面×64×32bit、quantized係数も32bitで接続する。DC予測は32bit、差分／加算は33bitで計算し、対応カテゴリを検査する。

DCT／IDCTのC定数はsigned16bit、小数14bit。次表をRTLと参照モデルで共用する。kが行、nが列。

```
  5793   5793   5793   5793   5793   5793   5793   5793
  8035   6811   4551   1598  -1598  -4551  -6811  -8035
  7568   3135  -3135  -7568  -7568  -3135   3135   7568
  6811  -1598  -8035  -4551   4551   8035   1598  -6811
  5793  -5793  -5793   5793   5793  -5793  -5793   5793
  4551  -8035   1598   6811  -6811  -1598   8035  -4551
  3135  -7568   7568  -3135  -3135   7568  -7568   3135
  1598  -4551   6811  -8035   8035  -6811   4551  -1598
```

変換器は8乗算器の内積演算器1組を2パスで共有する。入力8要素をレジスタ列から同時参照し、各行／列につき8結果を1結果/cycleで発行する。入力／転置／出力配列は各64位置を持ち、1行・列の8位置をまとめて読める分割レジスタまたは8バンク構成とする。単一ポートRAMから8値を同時に読む前提にしない。

転置・パス間はsigned48bit、積はsigned64bit、内積加算・丸めはsigned72bit。32bit入力と16bit定数の積、48bit中間と16bit定数の積を拡張して計算する。各パスでR14(z)=sign(z)*floor((abs(z)+8192)/16384)としてスケールを戻す。入力32bit×8項の第1パス、第2パスの範囲をこの幅で保持する。出力32bitへ戻す前に範囲を検査する。内部で飽和させず、範囲超過はエラー。IDCT最後の画素だけ128加算・0〜255飽和を行う。

演算パイプラインは乗算1段、加算木3段、丸め1段の初期構成。1パス64結果発行＋5cycle排出、2パス138cycleに加えて出力64cycleを要し、入力保持は別面で重ねる。下流停止による追加時間を測定し、256cycle/ブロックの目標を検証する。実際の256 MHzタイミングは合成評価まで未保証。

## 6. 量子化方式の確定

低速な2台反復除算器案を置き換え、1係数/cycle受付の32段パイプライン復元除算を初回実装に採用する。abs(coef)をunsigned32bitで表し、Qは8bit、商32bit・余り9bit。各段で1bitずつ処理し、最後に2*remainder>=Qなら商を+1、符号を戻す。これにより半分を絶対値の大きい側へ丸める整数式と一致する。符号・index・component等のメタデータも32段を通す。

停止時は全段を共通clock enableで止める。出力段が空または下流readyの場合に進める。表読出し1cycleと丸め1cycleを追加して最短34cycleの遅延、開始間隔1cycle。逆量子化は32×8bitをsigned40bitで乗算し、32bitへ範囲検査後に出す。自然順64係数を処理する。

## 7. bitstream・entropyの完了契約

最終係数だけではbyte側lastを即座に生成できないため、entropyが最終トークン転送後にfinish_valid/finish_readyをbitstreamへ送る。bitstreamは残りbitのパディングとstuffingを完了し、最終出力byteにlastを付ける。通常出力では1byteの末尾候補を保留し、次byteかfinishで最終判定する。finishは1回だけ受理する。

decodeは期待ブロック数を完了した後、残りビット0〜7が全1であることとinput_eofを確認する。peek不足でも短いコードを判定し、必要bit不足かつinput_eofなら入力不足。consumeと入力補充の同時発生では消費後の空きに補充する。FF00除去後のバイト列と符号ビットの順を変えない。

ACサイズ上限10、DC差分サイズ上限11。ZRLは16個の0を出力、EOBは残りのAC位置を0出力する。64位置を超えるrunとカテゴリを拒否する。符号語はMSB先行、負の追加bitはabs(value)をそのサイズで反転した値。DC予測更新はDCトークン確定時1回とする。

## 8. エラー・停止・初期化

| code | 内容 |
|---|---|
| 0 | エラーなし |
| 1 | 設定・寸法・アドレス範囲不正 |
| 2 | テーブル不正／未設定 |
| 3／4 | AXI read／write応答異常 |
| 5 | 入力不足 |
| 6 | Huffman・カテゴリ・マーカー不正 |
| 7 | 出力容量超過 |
| 8 | 演算範囲超過 |
| 9 | CPU停止要求 |
| 10 | 入力余剰・パディング不正 |

同じcycleの優先順位はread、write、設定、table、input、entropy、capacity、numeric、stop。最初のエラーを保持する。busyはERRORでも両DMA idleになるまで1。停止時は提示済みAR/AW/Wを成立させ、W全データとR/Bを回収する。エラー応答も要求数を解放する。返却データは停止専用の破棄経路へ受け付け、下流停止で回収を妨げない。

要求発行前に予約したデータ容量と送信データはclearまで不用意に解放しない。正常なDATAの解放は転送成立で行う。AXI接続先が永久に応答しない場合のタイムアウトは初回実装に設けず、システムリセットで復旧する。

## 9. 実装後に検証する事項

- 制御・テーブル・符号処理は参照モデルとの完全一致を合格条件にする。
- 演算は本書と同じ固定小数点モデルとの完全一致を先に確認する。外部JPEG復号との画素誤差は計測し、許容値を評価後に確定する。
- A4・300 dpi、4:4:4、圧縮率1:1、AXI平均500 nsでサイクル数・stall・FIFO最大使用量を確認する。平均だけでなく応答分布・read/write競合も変える。
- CPU変換・ヘッダ処理の実行時間、合成タイミング、外部実装の許容誤差は実装・評価時の残課題。本書の追加で初回RTLを記述できるが、100 ppm・256 MHz・最終画質達成の検証完了を意味しない。

## 10. セッション間で誤解しやすい補足

- 実装の開始手順と成果物は[実装引き継ぎ](../implementation_handoff.md)に従う。
- encodeのINPUT_BYTESはDRAMの有効サンプル総数と一致することを開始時に検査する。MCU端の複製・stride余白は数えない。decodeは指定JPEG範囲の全byteを入力し終わるまでread_doneを立てない。
- decodeのOUTPUT_LIMITは全成分の有効サンプル総数以上を必須とする。画像各領域の終端アドレスはbase+(height_c-1)*stride_c+width_c-1で別途範囲検査する。画素数とDRAM占有範囲を混同しない。CPUは入力／出力領域が重ならないよう確保する。
- JPEG_BASEは初回DMAの8byte整列条件を満たすようCPUがscan先頭を専用領域へ用意する。JPEGファイル内のSOS直後が必ず整列しているとは仮定しない。ヘッダ結合／コピーの時間もCPU性能評価に含める。
- decodeのブロック記述子はjpeg_ctrlのMCUカウンタが生成する。entropyは指定成分の1ブロックを完了してから次へ進む。encode側はDMAが付ける記述子と期待順を確認する。
- AXI要求数はAR/AW成立で加算、最終R/B成立で減算。同cycleなら両方を反映する。VALID提示中の要求には未成立でも容量を予約し、stop時に撤回しない。B応答だけで未送信Wを放棄しない。
- 画像ブロックRAMの物理配置・所有権はjpeg_topで一元化する。DMA内の「ブロック組立」はアドレス・端処理の論理機能で、同じ2面RAMを二重にインスタンス化しない。係数段間RAMと変換器転置RAMは別資源。
- decodeの量子化積はQを符号なし正値として41bit以上へゼロ拡張してからsigned乗算する。Q>=128を負値として扱わない。32bit×正8bitの結果はsigned40bitに収まり、32bitへの縮小を検査する。
- commit待ち中はAPBの指定kind/idをラッチする。commit成功後の再ロードは最初のDATA書込みでビットマップをクリアしてその位置だけを立てる。commit前に再書込みする場合は同じロードの上書きとして扱う。
- CONTROL.stopだけを書いたbusy中のアクセスはmodeビット値に関係なく受け付け、ラッチ済みmodeを変えない。startはdone/errorをクリア済みのIDLEだけ受け付ける。
- 外部の全JPEG形式対応を約束しない。初期対応範囲・テーブル数を満たす外部JPEGで相互運用を検証する。
