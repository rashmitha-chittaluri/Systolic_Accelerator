# ===========================================================
# Systolic Array Simulation Makefile (Cleaned for 8x8 Matrix)
# ===========================================================

TB_FILE = tb_file

# -------------------------
# Source File List
# -------------------------
SOURCES = \
  ../src/counter.sv \
  ../src/mac.sv \
  ./nonsynth_clock_gen.sv \
  ./nonsynth_reset_gen.sv \
  ../src/onehot_counter.sv \
  ../src/mac_array.sv \
  ../src/systolic_array.sv \
  ./testbench.sv

# -----------------------------------------------------------
# Icarus Verilog Build (Optional)
# -----------------------------------------------------------
iverilog:
	@echo "Compiling with Icarus Verilog..."
	@iverilog -g2012 -D IVERILOG -o ${TB_FILE} ${SOURCES}
	@vvp ${TB_FILE}
.PHONY: iverilog

# -----------------------------------------------------------
# Verilator Build and Simulation
# -----------------------------------------------------------
VERILATOR_OPTS = -sv --timing --trace-fst -timescale-override 1ns/1ps \
                 -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-MODDUP

verilator:
	@echo "Compiling and running with Verilator..."
	@verilator -o ${TB_FILE} ${VERILATOR_OPTS} --binary --top-module testbench ${SOURCES}
	@./obj_dir/${TB_FILE}
.PHONY: verilator

# -----------------------------------------------------------
# Run Both
# -----------------------------------------------------------
all: iverilog verilator
.PHONY: all

# -----------------------------------------------------------
# Clean Build Artifacts
# -----------------------------------------------------------
clean:
	@echo "Cleaning up generated files..."
	@rm -f ${TB_FILE}
	@rm -rf obj_dir/
	@rm -f iverilog.vcd
	@rm -f verilator.fst
.PHONY: clean
