# ==============================================================================
# ModelSim Batch Regression Script for VOQ 2x2 NoC Router
# Compatible: ModelSim 10.5b / QuestaSim / ModelSim SE
# ==============================================================================

vlib work
vmap work work

echo "=========================================================================="
echo ">>> COMPILING SYNTHESIZABLE NOC ROUTER RTL..."
echo "=========================================================================="
vlog rtl/router_top.v

echo ">>> RUNNING SCENARIO 1: Single Inport Flow & Basic FIFO Latency..."
vlog tb/TB_S1.v
vsim -c -do "run -all; quit" work.TB_S1

echo ">>> RUNNING SCENARIO 2: Port Contention & 3-Tier Arbitration Matrix..."
vlog tb/TB_S2.v
vsim -c -do "run -all; quit" work.TB_S2

echo ">>> RUNNING SCENARIO 3: Dynamic 3-Cycle Priority Aging & Starvation Defense..."
vlog tb/TB_S3.v
vsim -c -do "run -all; quit" work.TB_S3

echo ">>> RUNNING SCENARIO 4: Burst Mode Injection & FIFO Backpressure..."
vlog tb/TB_S4.v
vsim -c -do "run -all; quit" work.TB_S4

echo ">>> RUNNING SCENARIO 5: XOR Segment CRC Error Injection & Packet Drop..."
vlog tb/TB_S5.v
vsim -c -do "run -all; quit" work.TB_S5

echo ">>> RUNNING SCENARIO 6: Multi-Port Mixed Traffic Crossbar Stress..."
vlog tb/TB_S6.v
vsim -c -do "run -all; quit" work.TB_S6

echo "=========================================================================="
echo ">>> ALL 6 NOC ROUTER VERIFICATION SCENARIOS COMPLETED."
echo "=========================================================================="
quit -f
