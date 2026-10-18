VLOG ?= vlog
VSIM ?= vsim
VLIB ?= vlib
VCOVER ?= vcover
BUILD_DIR ?= build
WORK ?= $(BUILD_DIR)/work
LOGS_DIR ?= $(BUILD_DIR)/logs
RESULTS_DIR ?= $(BUILD_DIR)/results
TMP_DIR ?= $(BUILD_DIR)/tmp
COVERAGE_DIR ?= $(BUILD_DIR)/coverage
COVERAGE ?= 0

ifeq ($(OS),Windows_NT)
PYTHON ?= py -3
else
PYTHON ?= python3
endif

RTL := $(wildcard rtl/*.v)
VLOG_FLAGS := -work $(WORK) -sv -timescale "1ns/1ps" +incdir+rtl

# Coverage settings:
# - COVERAGE=1: enables code coverage (+cover=bcesft) on RTL and -coverage in vsim
# - Saves UCDB file per testbench into $(COVERAGE_DIR)/<testname>.ucdb
ifeq ($(COVERAGE),1)
COV_SUFFIX := _cov
VLOG_COV_FLAGS := +cover=bcesft
VSIM_COV_FLAGS := -coverage
export COVERAGE := 1
export COVERAGE_DIR := $(COVERAGE_DIR)
else
COV_SUFFIX :=
VLOG_COV_FLAGS :=
VSIM_COV_FLAGS :=
endif

# Mode selection:
# - Default (normal mode): no +acc, batch (-c), run -all; quit -> High speed
# - AI_DEBUG=1: +acc enabled, GUI mode (-gui), waveform logging (log -r /*), socket server, no run -all
ifeq ($(AI_DEBUG),1)
VSIM_FLAGS := -gui -voptargs=+acc -lib $(WORK) -wlf $(LOGS_DIR)/vsim.wlf $(VSIM_COV_FLAGS) -do "source tools/vsim_ai_debug.tcl"
export VSIM_AI_DEBUG := 1
VSIM_RUN = $(VSIM) $(VSIM_FLAGS) -l $(LOGS_DIR)/$(1).log
else
VSIM_FLAGS := -c -lib $(WORK) -wlf $(LOGS_DIR)/vsim.wlf $(VSIM_COV_FLAGS)
ifeq ($(COVERAGE),1)
VSIM_RUN = $(VSIM) $(VSIM_FLAGS) -do "coverage save -onexit -directive -cvg -codeAll $(COVERAGE_DIR)/$(1).ucdb" -do "run -all; quit" -l $(LOGS_DIR)/$(1).log
else
VSIM_RUN = $(VSIM) $(VSIM_FLAGS) -do "run -all; quit" -l $(LOGS_DIR)/$(1).log
endif
endif

.PHONY: all dirs lint vectors test unit integration interoperability clean coverage report-coverage
all: test

dirs:
	$(PYTHON) -c "import pathlib; [pathlib.Path(d).mkdir(parents=True, exist_ok=True) for d in ['$(BUILD_DIR)', '$(LOGS_DIR)', '$(RESULTS_DIR)', '$(TMP_DIR)', '$(COVERAGE_DIR)']]"

vectors: dirs
	$(PYTHON) tools/generate_vectors.py
	$(PYTHON) tools/check_interop.py --generate

lint: dirs $(WORK)
	$(PYTHON) tools/generate_rtl_tables.py --check
	$(VLOG) -lint $(VLOG_FLAGS) $(RTL)

$(WORK): dirs
	-$(VLIB) $(WORK)

$(WORK)/_unit_built$(COV_SUFFIX): dirs $(WORK) $(RTL) $(wildcard rtl/*.vh) sim/numeric_top.v sim/dma_top.v sim/numeric_tb.sv sim/bitstream_tb.sv sim/dma_tb.sv sim/storage_tb.sv sim/width_tb.sv sim/apb_tb.sv
	$(VLOG) $(VLOG_FLAGS) $(VLOG_COV_FLAGS) $(RTL) sim/numeric_top.v sim/dma_top.v sim/numeric_tb.sv sim/bitstream_tb.sv sim/dma_tb.sv sim/storage_tb.sv sim/width_tb.sv sim/apb_tb.sv
	$(PYTHON) -c "import pathlib; pathlib.Path('$@').touch()"

unit: dirs $(WORK)/_unit_built$(COV_SUFFIX)
	$(call VSIM_RUN,numeric_tb) numeric_tb
	$(call VSIM_RUN,bitstream_tb) bitstream_tb
	$(call VSIM_RUN,storage_tb) storage_tb
	$(call VSIM_RUN,dma_tb) dma_tb
	$(call VSIM_RUN,width_tb) width_tb
	$(call VSIM_RUN,apb_tb) apb_tb

$(WORK)/_top_built$(COV_SUFFIX): dirs $(WORK) $(RTL) $(wildcard rtl/*.vh) sim/top_tb.sv
	$(VLOG) $(VLOG_FLAGS) $(VLOG_COV_FLAGS) $(RTL) sim/top_tb.sv
	$(PYTHON) -c "import pathlib; pathlib.Path('$@').touch()"

integration: dirs vectors $(WORK)/_top_built$(COV_SUFFIX)
	$(call VSIM_RUN,top_tb) top_tb
	$(call VSIM_RUN,top_tb_variable) top_tb +variable

interoperability: integration
	$(PYTHON) tools/check_interop.py

test: lint unit interoperability

coverage: dirs
	$(MAKE) test COVERAGE=1
	$(MAKE) test-restart COVERAGE=1
	$(MAKE) test-tools COVERAGE=1
	$(MAKE) report-coverage

report-coverage: dirs
	$(PYTHON) tools/report_coverage.py

clean:
	$(PYTHON) -c "import shutil, os; [shutil.rmtree(d, ignore_errors=True) for d in ['build', 'work']]; [os.remove(f) for f in ['transcript', 'vsim.wlf', 'tcl_stacktrace.txt'] if os.path.exists(f)]"

.PHONY: performance performance-stress performance-variable
performance: vectors manuscript $(WORK)/_top_built$(COV_SUFFIX)
	$(PYTHON) tools/generate_performance_decode.py
	$(call VSIM_RUN,performance) top_tb +performance
	$(PYTHON) tools/check_performance.py

performance-stress: vectors manuscript $(WORK)/_top_built$(COV_SUFFIX)
	$(PYTHON) tools/generate_performance_decode.py stress
	$(call VSIM_RUN,performance_stress) top_tb +performance-stress
	$(PYTHON) tools/check_performance.py --stress

performance-variable: vectors manuscript $(WORK)/_top_built$(COV_SUFFIX)
	$(PYTHON) tools/generate_performance_decode.py variable
	$(call VSIM_RUN,performance_variable) top_tb +performance-variable
	$(PYTHON) tools/check_performance.py --variable

.PHONY: manuscript
manuscript: tests/data/a4_planar.bin tests/data/a4_manuscript.png tests/data/a4_conditions.json
tests/data/a4_planar.bin tests/data/a4_manuscript.png tests/data/a4_conditions.json &: tools/generate_manuscript.py
	$(PYTHON) tools/generate_manuscript.py

$(WORK)/_tool_built$(COV_SUFFIX): $(WORK) $(RTL) $(wildcard rtl/*.vh) sim/jpeg_tool_tb.sv
	$(VLOG) $(VLOG_FLAGS) $(VLOG_COV_FLAGS) $(RTL) sim/jpeg_tool_tb.sv
	$(PYTHON) -c "import pathlib; pathlib.Path('$@').touch()"

.PHONY: jpeg-tools test-tools
jpeg-tools: $(WORK)/_tool_built$(COV_SUFFIX)

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

test-restart: restart-vectors $(WORK)/_top_built$(COV_SUFFIX) jpeg-tools
	$(call VSIM_RUN,restart) top_tb +restart
	$(call VSIM_RUN,restart_variable) top_tb +restart-variable
	$(PYTHON) tools/test_restart_cli.py

# -----------------------------------------------------------------------------
# AI-assisted Interactive Debugging Mode
# - Launches QuestaSim in GUI mode
# - Keeps full signal visibility with -voptargs=+acc
# - Registers waveform logging for all signals via log -r /*
# - Does NOT execute run -all (waits at 0ns)
# - Starts Tcl TCP socket server for Python MCP Server connection
# -----------------------------------------------------------------------------
VSIM_DEBUG_FLAGS ?= -gui -voptargs=+acc -lib $(WORK) -l $(LOGS_DIR)/debug.log -wlf $(LOGS_DIR)/debug.wlf $(VSIM_COV_FLAGS) -do "source tools/vsim_ai_debug.tcl"

.PHONY: ai-debug-tool ai-debug-top
ai-debug-tool: $(WORK)/_tool_built$(COV_SUFFIX)
	$(PYTHON) -c "import pathlib; pathlib.Path('$(BUILD_DIR)/debug_job').mkdir(parents=True, exist_ok=True)"
	$(VSIM) $(VSIM_DEBUG_FLAGS) jpeg_tool_tb +JOB_DIR=$(BUILD_DIR)/debug_job

ai-debug-top: vectors $(WORK)/_top_built$(COV_SUFFIX)
	$(VSIM) $(VSIM_DEBUG_FLAGS) top_tb

