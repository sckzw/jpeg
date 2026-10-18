VLOG ?= vlog
VSIM ?= vsim
VLIB ?= vlib
BUILD_DIR ?= build
WORK ?= $(BUILD_DIR)/work
LOGS_DIR ?= $(BUILD_DIR)/logs
RESULTS_DIR ?= $(BUILD_DIR)/results
TMP_DIR ?= $(BUILD_DIR)/tmp

ifeq ($(OS),Windows_NT)
PYTHON ?= py -3
else
PYTHON ?= python3
endif

RTL := $(wildcard rtl/*.v)
VLOG_FLAGS := -work $(WORK) -sv -timescale "1ns/1ps" +incdir+rtl

# Mode selection:
# - Default (normal mode): no +acc, batch (-c), run -all; quit -> High speed
# - AI_DEBUG=1: +acc enabled, GUI mode (-gui), waveform logging (log -r /*), socket server, no run -all
ifeq ($(AI_DEBUG),1)
VSIM_FLAGS := -gui -voptargs=+acc -lib $(WORK) -wlf $(LOGS_DIR)/vsim.wlf -do "source tools/vsim_ai_debug.tcl"
export VSIM_AI_DEBUG := 1
else
VSIM_FLAGS := -c -lib $(WORK) -wlf $(LOGS_DIR)/vsim.wlf -do "run -all; quit"
endif

.PHONY: all dirs lint vectors test unit integration interoperability clean
all: test

dirs:
	$(PYTHON) -c "import pathlib; [pathlib.Path(d).mkdir(parents=True, exist_ok=True) for d in ['$(BUILD_DIR)', '$(LOGS_DIR)', '$(RESULTS_DIR)', '$(TMP_DIR)']]"

vectors: dirs
	$(PYTHON) tools/generate_vectors.py
	$(PYTHON) tools/check_interop.py --generate

lint: dirs $(WORK)
	$(PYTHON) tools/generate_rtl_tables.py --check
	$(VLOG) -lint $(VLOG_FLAGS) $(RTL)

$(WORK): dirs
	-$(VLIB) $(WORK)

$(WORK)/_unit_built: dirs $(WORK) $(RTL) $(wildcard rtl/*.vh) sim/numeric_top.v sim/dma_top.v sim/numeric_tb.sv sim/bitstream_tb.sv sim/dma_tb.sv sim/storage_tb.sv sim/width_tb.sv sim/apb_tb.sv
	$(VLOG) $(VLOG_FLAGS) $(RTL) sim/numeric_top.v sim/dma_top.v sim/numeric_tb.sv sim/bitstream_tb.sv sim/dma_tb.sv sim/storage_tb.sv sim/width_tb.sv sim/apb_tb.sv
	$(PYTHON) -c "import pathlib; pathlib.Path('$@').touch()"

unit: dirs $(WORK)/_unit_built
	$(VSIM) $(VSIM_FLAGS) -l $(LOGS_DIR)/numeric_tb.log numeric_tb
	$(VSIM) $(VSIM_FLAGS) -l $(LOGS_DIR)/bitstream_tb.log bitstream_tb
	$(VSIM) $(VSIM_FLAGS) -l $(LOGS_DIR)/storage_tb.log storage_tb
	$(VSIM) $(VSIM_FLAGS) -l $(LOGS_DIR)/dma_tb.log dma_tb
	$(VSIM) $(VSIM_FLAGS) -l $(LOGS_DIR)/width_tb.log width_tb
	$(VSIM) $(VSIM_FLAGS) -l $(LOGS_DIR)/apb_tb.log apb_tb

$(WORK)/_top_built: dirs $(WORK) $(RTL) $(wildcard rtl/*.vh) sim/top_tb.sv
	$(VLOG) $(VLOG_FLAGS) $(RTL) sim/top_tb.sv
	$(PYTHON) -c "import pathlib; pathlib.Path('$@').touch()"

integration: dirs vectors $(WORK)/_top_built
	$(VSIM) $(VSIM_FLAGS) -l $(LOGS_DIR)/top_tb.log top_tb
	$(VSIM) $(VSIM_FLAGS) -l $(LOGS_DIR)/top_tb_variable.log top_tb +variable

interoperability: integration
	$(PYTHON) tools/check_interop.py

test: lint unit interoperability

clean:
	$(PYTHON) -c "import shutil, os; [shutil.rmtree(d, ignore_errors=True) for d in ['build', 'work']]; [os.remove(f) for f in ['transcript', 'vsim.wlf', 'tcl_stacktrace.txt'] if os.path.exists(f)]"

.PHONY: performance performance-stress performance-variable
performance: vectors manuscript $(WORK)/_top_built
	$(PYTHON) tools/generate_performance_decode.py
	$(VSIM) $(VSIM_FLAGS) -l $(LOGS_DIR)/performance.log top_tb +performance
	$(PYTHON) tools/check_performance.py

performance-stress: vectors manuscript $(WORK)/_top_built
	$(PYTHON) tools/generate_performance_decode.py stress
	$(VSIM) $(VSIM_FLAGS) -l $(LOGS_DIR)/performance_stress.log top_tb +performance-stress
	$(PYTHON) tools/check_performance.py --stress

performance-variable: vectors manuscript $(WORK)/_top_built
	$(PYTHON) tools/generate_performance_decode.py variable
	$(VSIM) $(VSIM_FLAGS) -l $(LOGS_DIR)/performance_variable.log top_tb +performance-variable
	$(PYTHON) tools/check_performance.py --variable

.PHONY: manuscript
manuscript: tests/data/a4_planar.bin tests/data/a4_manuscript.png tests/data/a4_conditions.json
tests/data/a4_planar.bin tests/data/a4_manuscript.png tests/data/a4_conditions.json &: tools/generate_manuscript.py
	$(PYTHON) tools/generate_manuscript.py

$(WORK)/_tool_built: $(WORK) $(RTL) $(wildcard rtl/*.vh) sim/jpeg_tool_tb.sv
	$(VLOG) $(VLOG_FLAGS) $(RTL) sim/jpeg_tool_tb.sv
	$(PYTHON) -c "import pathlib; pathlib.Path('$@').touch()"

.PHONY: jpeg-tools test-tools
jpeg-tools: $(WORK)/_tool_built

test-tools: jpeg-tools
	$(PYTHON) tools/test_jpeg_tool.py

.PHONY: test-internet-images
test-internet-images: jpeg-tools
	$(PYTHON) tools/test_internet_images.py $(FILTER)

.PHONY: test-internet-five
test-internet-five: jpeg-tools
	$(PYTHON) tools/test_internet_five.py $(FILTER)

.PHONY: restart-vectors test-restart
restart-vectors:
	$(PYTHON) tools/generate_restart_vectors.py

test-restart: restart-vectors $(WORK)/_top_built jpeg-tools
	$(VSIM) $(VSIM_FLAGS) -l $(LOGS_DIR)/restart.log top_tb +restart
	$(VSIM) $(VSIM_FLAGS) -l $(LOGS_DIR)/restart_variable.log top_tb +restart-variable
	$(PYTHON) tools/test_restart_cli.py

# -----------------------------------------------------------------------------
# AI-assisted Interactive Debugging Mode
# - Launches QuestaSim in GUI mode
# - Keeps full signal visibility with -voptargs=+acc
# - Registers waveform logging for all signals via log -r /*
# - Does NOT execute run -all (waits at 0ns)
# - Starts Tcl TCP socket server for Python MCP Server connection
# -----------------------------------------------------------------------------
VSIM_DEBUG_FLAGS ?= -gui -voptargs=+acc -lib $(WORK) -l $(LOGS_DIR)/debug.log -wlf $(LOGS_DIR)/debug.wlf -do "source tools/vsim_ai_debug.tcl"

.PHONY: ai-debug-tool ai-debug-top
ai-debug-tool: $(WORK)/_tool_built
	$(PYTHON) -c "import pathlib; pathlib.Path('$(BUILD_DIR)/debug_job').mkdir(parents=True, exist_ok=True)"
	$(VSIM) $(VSIM_DEBUG_FLAGS) jpeg_tool_tb +JOB_DIR=$(BUILD_DIR)/debug_job

ai-debug-top: vectors $(WORK)/_top_built
	$(VSIM) $(VSIM_DEBUG_FLAGS) top_tb

