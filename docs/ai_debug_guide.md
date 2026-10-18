# QuestaSim AIデバッグモード & MCPサーバー連携ガイド

本ドキュメントでは、QuestaSimのシミュレーション環境において、**「通常高速テスト実行モード」**と**「AIデバッグモード（波形ロギング + MCPサーバー連携）」**の2つのモードを切り替えて運用する方法について解説します。

---

## 1. 2つの実行モードの比較

| 項目 | 通常モード（全テスト実行） | AIデバッグモード（MCP連携） |
|---|---|---|
| **目的** | CI・回帰テスト・高速一括検証 | AIによる自律波形解析・対話型デバッグ |
| **GUI** | なし（CUI / バッチ: `-c`） | **あり（GUI: `-gui`）** |
| **最適化 (`-voptargs`)** | なし（Vopt最適化フル適用で高速） | **`+acc`（全信号・内部レジスタの可視性確保）** |
| **波形ロギング** | なし（WLFファイル生成抑制） | **事前登録（`log -r /*`）** |
| **シミュレーション実行** | `run -all; quit` で最後まで完走 | **`run -all` は実行しない（0nsで待機）** |
| **外部通信** | なし | **Tclソケットサーバー起動（port: 5678）** |

---

## 2. 通常モード（全テスト・高速実行）の使い方

波形観測を行わず、`-voptargs=+acc` を外して QuestaSim のコンパイラ最適化を最大限に活用します。

### CLIツール（`jpeg_tool.py`）での実行
```powershell
# エンコード
py -3 tools/jpeg_tool.py encode input.png output.jpg --sampling 444 --quant 16

# デコード
py -3 tools/jpeg_tool.py decode input.jpg output.png
```

### Makefileでの一括回帰テスト（通常モード）
```powershell
# 実画像テスト (高速・全画像)
make test-internet-images
make test-internet-five

# 単体テスト・結合テスト
make unit
make integration

# 全体回帰テスト
make test
```

---

## 3. AIデバッグモードの使い方（ワンタッチ切り替え）

### 3.1 `make <target> AI_DEBUG=1` での切り替え（推奨）

Makefile に **`AI_DEBUG=1`** を付与するだけで、**すべてのテストターゲットが自動的にAIデバッグモード（GUI起動・+acc有効・全波形ロギング `log -r /*`・ソケット待機）に切り替わります**。

```powershell
# 1. 実画像テストをデバッグモードで起動 (全画像)
make test-internet-images AI_DEBUG=1

# 2. 特定の画像だけをピンポイントでデバッグ起動 (例: flower のみ)
make test-internet-images FILTER=flower AI_DEBUG=1

# 3. test-internet-five で特定の画像だけをデバッグ起動 (例: hopper のみ)
make test-internet-five FILTER=hopper AI_DEBUG=1

# 4. 単体テスト (unit) や 結合テスト (integration) をデバッグモードで起動
make unit AI_DEBUG=1
make integration AI_DEBUG=1
```

### 3.2 CLIツール（`jpeg_tool.py`）から起動する場合
`--gui`（または `--ai-debug`）オプションを付与します。
```powershell
py -3 tools/jpeg_tool.py decode tests/data/internet/flower_baseline.jpg build/flower.png --gui
```
- 中間データは `build/debug_job/` に保持されます。
- QuestaSim GUIが開き、以下の処理が自動で行われます：
  1. `log -r /*` により全階層の信号を波形ロギング対象に登録
  2. Waveウィンドウが開き、主要なバス・クロック・DUT信号を追加
  3. `run -all` は実行せず、時刻 0ns で停止
  4. バックグラウンドで Tcl ソケットサーバー（デフォルト port 5678）が待機

#### 方法 B: Makefile から起動
```powershell
# jpeg_tool_tb をGUIで起動
make ai-debug-tool

# トップ検証 (top_tb) をGUIで起動
make ai-debug-top
```

---

## 4. MCP（Model Context Protocol）サーバーの設定

Pythonの FastMCP ライブラリを用いたサーバー（[tools/vsim_mcp.py](file:///d:/Users/shuichi/Documents/AI/jpeg/tools/vsim_mcp.py)）が用意されています。

### 4.1 MCPクライアントへの登録設定

#### Antigravity / Claude Code / Cursor / VS Code (`mcp_config.json`)
```json
{
  "mcpServers": {
    "questasim": {
      "command": "py",
      "args": [
        "-3",
        "d:/Users/shuichi/Documents/AI/jpeg/tools/vsim_mcp.py"
      ],
      "env": {
        "VSIM_HOST": "127.0.0.1",
        "VSIM_PORT": "5678"
      }
    }
  }
}
```

---

## 5. AIから利用可能なデバッグ用MCPツール一覧

| ツール名 | 説明 | 例 / 引数 |
|---|---|---|
| `vsim_run` | 指定時間シミュレーションを進める | `time_spec="500 ns"`, `time_spec="10 us"` |
| `vsim_run_cycles` | クロックサイクル単位でシミュレーションを進める | `cycles=128` (256MHz設計基準) |
| `vsim_examine` | 信号値（レジスタ・ワイヤ・ステート）を読み出す | `signal="/jpeg_tool_tb/dut/state"`, `radix="hex"` |
| `vsim_examine_multiple`| 複数信号の値を一括読み出し | `signals=["/tb/dut/clk", "/tb/dut/valid"]` |
| `vsim_add_wave` | GUIの波形ウィンドウに信号を追加 | `signals="/jpeg_tool_tb/dut/u_quant/*"` |
| `vsim_delete_wave` | GUIの波形ウィンドウから指定信号を削除 | `signals="/jpeg_tool_tb/psel"` または `signals="*"` |
| `vsim_clear_wave` | GUIの波形ウィンドウから全信号を一括クリア | 引数なし |
| `vsim_find_signals` | 信号名やポート・レジスタをワイルドカード検索 | `pattern="*valid*"` |
| `vsim_get_now` | 現在のシミュレーション時刻を取得 | 引数なし |
| `vsim_wave_zoom_full` | 波形ウィンドウを全体表示（Zoom Full）に更新 | 引数なし |
| `vsim_set_breakpoint` | ブレークポイントを設定 | `location="sim/jpeg_tool_tb.sv:520"` |
| `vsim_restart` | シミュレーションを0nsに戻し、波形ログを再設定 | 引数なし |
| `vsim_exec` | 任意の QuestaSim Tcl コマンドを直接実行 | `command="checkpoint"` など |

---

## 6. AIとの対話デバッグ例

QuestaSim GUI を立ち上げた状態で、AIに以下のように話しかけるだけで操作・調査が可能です：

> **あなた**: 「`jpeg_top` の主要信号（`start`, `done`, `state`, `m_axi_awvalid`, `m_axi_wvalid`）を波形に追加して、1000サイクル進めてみて」
> 
> **AI**: 
> 1. `vsim_add_wave` で各信号をWave画面に追加
> 2. `vsim_run_cycles(cycles=1000)` を実行
> 3. `vsim_wave_zoom_full` で波形の表示範囲を自動調整
> 4. 「1000サイクル（3906.25 ns）進めました。GUIの波形に追加されています」と回答。

> **あなた**: 「なぜステートマシンが次の状態に進まないのか、関連するReady/Valid信号の値を調べて」
> 
> **AI**:
> 1. `vsim_examine_multiple` で関連信号を読み出し
> 2. 「`m_axi_wready` がLowのままであるため、AXI Writeチャネルのハンドシェイク待ちでストールしています」と診断。
