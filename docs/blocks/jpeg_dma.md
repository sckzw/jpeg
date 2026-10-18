# DMAブロック構成

AXIリードとAXIライトは独立モジュールとする。jpeg_dmaという一体モジュールは実装しない。

- [jpeg_dma_read](jpeg_dma_read.md)：AR／R、画像・JPEG読出し、入力ブロック組立。
- [jpeg_dma_write](jpeg_dma_write.md)：AW／W／B、JPEG・復号画像書込み。

双方をjpeg_topでAXI4マスターの各チャネルへ接続する。開始・停止・完了・エラーの集約はjpeg_ctrlが担当する。各方向で独立した最大8要求、要求FIFOとデータ容量を管理する。
