# VOQ 2×2 Network-on-Chip (NoC) Router
### Virtual Output Queuing Architecture with Cycle-Accurate Ingress-to-Egress Latency Tracking

[![Language: Verilog-2001](https://img.shields.io/badge/Language-Verilog--2001-blue.svg)](rtl/router_top.v)
[![Simulation: ModelSim](https://img.shields.io/badge/Simulation-ModelSim%2010.5b%20%7C%20QuestaSim-orange.svg)](sim/run_regression.do)
[![Synthesis: Intel FPGA](https://img.shields.io/badge/Synthesis-Intel%20Quartus%20Prime-darkgreen.svg)](constraints/noc_router_timing.sdc)
[![Timing: 100 MHz Target](https://img.shields.io/badge/Timing-100%20MHz%20SDC%20Constrained-purple.svg)](constraints/noc_router_timing.sdc)
[![Track: SanDisk Hackathon](https://img.shields.io/badge/Track-SanDisk%20VLSI%20Design%20Challenge-red.svg)](docs/noc_router_architecture_presentation.pptx)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

A synthesizable, 32-bit packet-switched **2×2 Network-on-Chip (NoC) Router** engineered in Verilog-2001. The router integrates **Virtual Output Queuing (VOQ)** to completely eliminate Head-of-Line (HoL) blocking, a combinational 5-segment XOR CRC detection engine, a 3-tier arbitration matrix (Priority > 3-cycle Dynamic Aging > Round-Robin), and an on-chip **per-packet injection-to-exit cycle latency tracking instrumentation engine**.

---

## 1. Microarchitectural Dataflow

```
                Inport 0 [31:0]                        Inport 1 [31:0]
                      │                                      │
                      ▼                                      ▼
             ┌─────────────────┐                    ┌─────────────────┐
  Stage 1:   │ Inport Register │                    │ Inport Register │
             └────────┬────────┘                    └────────┬────────┘
                      │                                      │
                      ▼                                      ▼
             ┌─────────────────┐                    ┌─────────────────┐
             │ Parser & XOR CRC│                    │ Parser & XOR CRC│
             └────────┬────────┘                    └────────┬────────┘
                      │                                      │
                      ▼                                      ▼
             ┌─────────────────┐                    ┌─────────────────┐
             │ 1:2 Egress Demux│                    │ 1:2 Egress Demux│
             └───┬─────────┬───┘                    └───┬─────────┬───┘
                 │         │                            │         │
        Dest=0   │         │ Dest=1            Dest=0   │         │ Dest=1
        ┌────────┘         └────────┐          ┌────────┘         └────────┐
        ▼                           ▼          ▼                           ▼
  Stage 2:
 ┌─────────────┐             ┌─────────────┐ ┌─────────────┐             ┌─────────────┐
 │ VOQ_FIFO_00 │             │ VOQ_FIFO_01 │ │ VOQ_FIFO_10 │             │ VOQ_FIFO_11 │
 │ (To Port 0) │             │ (To Port 1) │ │ (To Port 0) │             │ (To Port 1) │
 └──────┬──────┘             └──────┬──────┘ └──────┬──────┘             └──────┬──────┘
        │                           │               │                           │
        └──────────────┐            │  ┌────────────┘                           │
                       ▼            ▼  ▼                                        ▼
  Stage 3:      ┌─────────────┐              ┌─────────────┐
                │  Arbiter 0  │              │  Arbiter 1  │
                │ (Outport 0) │              │ (Outport 1) │
                └──────┬──────┘              └──────┬──────┘
                       │                            │
                       ▼                            ▼
  Stage 4:      ┌──────────────────────────────────────────┐
                │           2×2 Crossbar Switch            │
                └─────────────────────┬────────────────────┘
                                      │
                        ┌─────────────┴─────────────┐
                        ▼                           ▼
                  Outport Port 0              Outport Port 1
                (Cycle Latency Tag)         (Cycle Latency Tag)
```

### Microarchitectural Pipeline Stages
1. **Stage 1 (Ingress & Parity Check)**: Latches incoming 32-bit packets. The combinational 5-segment XOR reduction tree validates packet integrity in zero clock cycles. Corrupted packets trigger error flags (`err_crc`) and are dropped before entering queue buffers.
2. **Stage 2 (VOQ Ingress Queuing)**: Non-blocking demultiplexers steer validated packets into destination-specific FIFO buffers (`VOQ_00`, `VOQ_01`, `VOQ_10`, `VOQ_11`). Each FIFO is 8 words deep and stores packet data alongside its 32-bit global injection timestamp.
3. **Stage 3 (3-Tier Arbitration Matrix)**: Dual independent arbiters evaluate contending requests for Outport 0 and Outport 1 concurrently without crossbar contention.
4. **Stage 4 (Crossbar & Instrumentation)**: Crossbar transfers granted packets to egress ports. The instrumentation logic subtracts the queued injection timestamp from the egress cycle counter to yield instant packet latency ($T_{\text{latency}} = T_{\text{egress}} - T_{\text{inject}}$).

---

## 2. Packet Framing Specification (32-Bit)

$$\text{Packet}[31:0] = \{ \text{Priority}[31:30],\, \text{Dest}[29],\, \text{PktID}[28:24],\, \text{Payload}[23:5],\, \text{CRC}[4:0] \}$$

| Bit Field | Identifier | Width | Function |
| :---: | :---: | :---: | :--- |
| `[31:30]` | **PRIORITY** | 2 bits | Urgency class: `2'b11` (Critical) > `2'b10` (High) > `2'b01` (Medium) > `2'b00` (Best Effort). |
| `[29]` | **DEST** | 1 bit | Egress port destination: `1'b0` = Outport 0, `1'b1` = Outport 1. |
| `[28:24]` | **PKT_ID** | 5 bits | Unique 5-bit packet sequence tracker for latency and trajectory monitoring. |
| `[23:5]` | **PAYLOAD** | 19 bits | General-purpose data transport across the NoC fabric. |
| `[4:0]` | **CRC** | 5 bits | 5-segment XOR parity reduction over bits `[31:5]` (27 data bits $\to$ 5 parity bits). |

### Combinational XOR Parity Formulation
$$\begin{aligned}
\text{CRC}[0] &= \bigoplus \text{Data}[4:0] = \text{Pkt}[9:5] \\
\text{CRC}[1] &= \bigoplus \text{Data}[9:5] = \text{Pkt}[14:10] \\
\text{CRC}[2] &= \bigoplus \text{Data}[15:10] = \text{Pkt}[20:15] \\
\text{CRC}[3] &= \bigoplus \text{Data}[21:16] = \text{Pkt}[26:21] \\
\text{CRC}[4] &= \bigoplus \text{Data}[26:22] = \text{Pkt}[31:27]
\end{aligned}$$

---

## 3. Starvation-Free Arbitration Matrix

To resolve output port contention when both `VOQ_0X` and `VOQ_1X` assert valid requests, each arbiter enforces a 3-tier arbitration hierarchy:

$$\text{Effective Priority} = \text{Raw Priority} + \left\lfloor \frac{\text{Wait Cycles}}{3} \right\rfloor$$

1. **Tier 1 (Priority Dominance)**: Packets with higher effective priority are granted crossbar access immediately.
2. **Tier 2 (3-Cycle Aging Compensation)**: Packets denied grant increment an internal 2-bit aging counter. Every 3 continuous stall cycles, their effective priority is boosted by $+1$, guaranteeing that best-effort packets (`2'b00`) eventually supersede stalled critical traffic (`2'b11`).
3. **Tier 3 (Fair Round-Robin Tie-Breaking)**: When effective priorities are identical, the arbiter toggles between inports based on previous grant history, ensuring exact 50/50 bandwidth allocation under saturation.

---

## 4. Hardware Latency Instrumentation Engine

Unlike typical NoC simulation wrappers that measure latency off-chip in the testbench, this design embeds **hardware latency profiling registers** on-chip:
- **`latency_out0` / `latency_out1` [31:0]**: Instantaneous cycle count for the packet currently exiting the crossbar.
- **`max_latency0` / `max_latency1` [31:0]**: High-water mark register recording the worst-case queuing latency observed since system reset.
- **`throughput_cnt` [31:0]**: Cumulative tally of successfully retired packets.
- **`conflict_cnt` [31:0]**: Count of clock cycles where both inports requested the same egress port simultaneously.

---

## 5. Verification Regression Suite

The design is verified across six comprehensive ModelSim testbenches located in `tb/`:

| Test Suite | Focus Area | Verification Objectives |
| :--- | :--- | :--- |
| **`TB_S1.v`** | Single Inport Flow | Validates packet framing, FIFO enqueue/dequeue, and baseline 2-cycle latency. |
| **`TB_S2.v`** | Port Contention | Dual-port injection targeting the same outport; verifies priority preemption and conflict logging. |
| **`TB_S3.v`** | Priority Aging | Sustained high-priority traffic competing with low-priority packets; verifies starvation prevention after 3 wait cycles. |
| **`TB_S4.v`** | Burst Backpressure | Consecutive 8-packet bursts; verifies FIFO full flag assertion and lossless flow control. |
| **`TB_S5.v`** | Error Handling | Single-bit parity flips; verifies combinational error detection (`err_crc`) and packet suppression. |
| **`TB_S6.v`** | Stress Testing | Pseudo-random traffic pattern across all 4 priority classes, both egress ports, and full crossbar utilization. |

Detailed cycle-accurate waveform reports are documented in [`docs/output_router_waveform.pdf`](docs/output_router_waveform.pdf) and [`docs/output_router_waveform_new1.pdf`](docs/output_router_waveform_new1.pdf).

---

## 6. Directory Layout

```
VOQ-2x2-NoC-Router/
├── README.md                           # Master architectural specification
├── .gitignore                          # Simulation and compilation exclusions
├── rtl/
│   └── router_top.v                    # Synthesizable RTL (VOQ FIFOs, Arbiters, Crossbar, Instrumentation)
├── constraints/
│   └── noc_router_timing.sdc           # 100 MHz Synopsys Design Constraints
├── sim/
│   └── run_regression.do               # ModelSim batch regression execution macro
├── tb/
│   ├── TB_S1.v                         # Scenario 1: Basic flow testbench
│   ├── TB_S2.v                         # Scenario 2: Contention & arbitration testbench
│   ├── TB_S3.v                         # Scenario 3: 3-cycle aging testbench
│   ├── TB_S4.v                         # Scenario 4: FIFO burst & backpressure testbench
│   ├── TB_S5.v                         # Scenario 5: CRC parity error testbench
│   └── TB_S6.v                         # Scenario 6: Mixed stress testbench
└── docs/
    ├── noc_router_architecture_presentation.pptx  # Architectural slides
    ├── output_router_waveform.pdf                 # ModelSim simulation waveform report
    └── output_router_waveform_new1.pdf            # Upgraded waveform analysis report
```

---

## 7. Simulation Quick Start

### ModelSim Batch Regression
```bash
cd VOQ-2x2-NoC-Router
vsim -c -do sim/run_regression.do
```

### Manual Individual Testbench Run
```bash
vlib work
vlog rtl/router_top.v tb/TB_S3.v
vsim -c -do "run -all; quit" work.TB_S3
```

---

## 8. Authors & References

- **Lead RTL Designer**: Hari Kruthik SK  
- **Context**: VIT-SanDisk Hackathon — Track 3: High-Performance Network-on-Chip Router Architecture  
- **License**: Released under the [MIT License](LICENSE).
