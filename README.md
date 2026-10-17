# VOQ 2×2 Network-on-Chip (NoC) Router with Cycle-Accurate Latency Tracking

[![Language: Verilog-2001](https://img.shields.io/badge/Language-Verilog--2001-blue.svg)]()
[![Simulation: ModelSim](https://img.shields.io/badge/Simulation-ModelSim%2010.5b-orange.svg)]()
[![Target: Intel FPGA](https://img.shields.io/badge/Synthesis-Intel%20Quartus%20Prime-lightgrey.svg)]()
[![Track: VIT-SanDisk Hackathon](https://img.shields.io/badge/Event-VIT--SanDisk%20Hackathon%20Track%203-red.svg)]()

A high-performance, 32-bit packet-switched **2×2 Network-on-Chip (NoC) Router** designed in synthesizable Verilog-2001. The router integrates **Virtual Output Queuing (VOQ)** to completely eliminate Head-of-Line (HoL) blocking, combinational XOR parity CRC detection, a 3-tier arbitration matrix (Priority > 3-cycle Aging > Round-Robin), and an upgraded on-chip **per-packet injection-to-exit cycle latency tracking engine**.

---

## 1. Architectural Highlights

```
                 Port 0 Packet [31:0]                   Port 1 Packet [31:0]
                          │                                      │
                          ▼                                      ▼
                  ┌──────────────┐                       ┌──────────────┐
                  │input_register│                       │input_register│
                  └───────┬──────┘                       └───────┬──────┘
                          │                                      │
                          ▼                                      ▼
                  ┌──────────────┐                       ┌──────────────┐
                  │ parser & CRC │                       │ parser & CRC │
                  └───────┬──────┘                       └───────┬──────┘
                          │                                      │
                          ▼                                      ▼
                  ┌──────────────┐                       ┌──────────────┐
                  │    demux     │                       │    demux     │
                  └───┬──────┬───┘                       └───┬──────┬───┘
                      │      │                               │      │
            Dest=0    │      │ Dest=1              Dest=0    │      │ Dest=1
            ┌─────────┘      └────────┐          ┌───────────┘      └────────┐
            ▼                         ▼          ▼                           ▼
     ┌──────────────┐          ┌──────────────┐ ┌──────────────┐      ┌──────────────┐
     │  VOQ_FIFO_00 │          │  VOQ_FIFO_01 │ │  VOQ_FIFO_10 │      │  VOQ_FIFO_11 │
     │ (Dest Out 0) │          │ (Dest Out 1) │ │ (Dest Out 0) │      │ (Dest Out 1) │
     └──────┬───────┘          └──────┬───────┘ └──────┬───────┘      └──────┬───────┘
            │                         │                │                     │
            └───────────┐             │   ┌────────────┘                     │
                        ▼             ▼   ▼                                  ▼
                 ┌─────────────┐               ┌─────────────┐
                 │  Arbiter 0  │               │  Arbiter 1  │
                 │(Dest Out 0) │               │(Dest Out 1) │
                 └──────┬──────┘               └──────┬──────┘
                        │                             │
                        ▼                             ▼
                 ┌───────────────────────────────────────────┐
                 │            2×2 Crossbar Switch            │
                 └────────────────────┬──────────────────────┘
                                      │
                        ┌─────────────┴─────────────┐
                        ▼                           ▼
                   Output Port 0               Output Port 1
                 (Latency Tracking)          (Latency Tracking)
```

### Key Engineering Features
1. **Zero Head-of-Line Blocking**: Packets are routed immediately into separate depth-8 FIFOs classified by destination port (`VOQ_00`, `VOQ_01`, `VOQ_10`, `VOQ_11`).
2. **Instantaneous Combinational Error Checking**: A 5-bit XOR segment parity reduction tree evaluates 27-bit packet data combinations concurrently with zero pipeline delay.
3. **Starvation-Free 3-Tier Arbiter**:
   - **Level 1 (Priority)**: Packets with priority `3` preempt lower priorities.
   - **Level 2 (3-Cycle Aging)**: Packets waiting without grant accumulate effective priority every 3 cycles ($Eff = Prio + Age$).
   - **Level 3 (Round-Robin)**: Equal effective priority ties are resolved fairly using historical grant state.
4. **Hardware Latency Instrumentation (Upgrade 1)**:
   - Each FIFO slot stores the global 32-bit cycle counter value at write time.
   - Upon grant and exit, instantaneous packet latency ($T_{\text{exit}} - T_{\text{inject}}$) is passed to the performance monitor.
   - Computes real-time `throughput_cnt`, `conflict_cnt`, `max_latency`, and cumulative `avg_latency`.

---

## 2. Packet Framing Specification (32-Bit)

| Bit Field | Name | Width | Description |
| :---: | :---: | :---: | :--- |
| `[31:30]` | **PRIORITY** | 2 bits | Packet urgency class: `2'b11` (Highest) to `2'b00` (Lowest/Best-Effort). |
| `[29]` | **DEST** | 1 bit | Egress port selection: `1'b0` = Output Port 0, `1'b1` = Output Port 1. |
| `[28:24]` | **PKT_ID** | 5 bits | Unique identifier tracking packet trajectory through arbitration. |
| `[23:5]` | **PAYLOAD** | 19 bits | Data payload carried across NoC fabric. |
| `[4:0]` | **CRC** | 5 bits | 5-segment XOR parity over bits `[31:5]` ($27\text{ bits} \to 5\text{ parity bits}$). |

### 5-Bit XOR Segment Parity Reduction
- $\text{CRC}[0] = \bigoplus \text{Data}[4:0]$
- $\text{CRC}[1] = \bigoplus \text{Data}[9:5]$
- $\text{CRC}[2] = \bigoplus \text{Data}[15:10]$
- $\text{CRC}[3] = \bigoplus \text{Data}[21:16]$
- $\text{CRC}[4] = \bigoplus \text{Data}[26:22]$

---

## 3. Verification Suite & Test Scenarios

The testbench suite covers six comprehensive verification scenarios in ModelSim (`tb/`):
- **`TB_S1.v` (Single Inport Flow)**: Basic packet parsing, FIFO enqueue/dequeue, and single-port throughput.
- **`TB_S2.v` (Port Contention & Conflict)**: Concurrent packets from Inport 0 and Inport 1 targeting the same Output Port.
- **`TB_S3.v` (Aging & Starvation Prevention)**: Low-priority packet aging over sustained high-priority traffic to guarantee grant.
- **`TB_S4.v` (Burst Mode & FIFO Backpressure)**: Consecutive 8-packet burst filling VOQ buffers to verify full/empty flow control.
- **`TB_S5.v` (CRC Error Injection)**: Intentional single-bit parity flip verifying error flagging and demux suppression.
- **`TB_S6.v` (Multi-Port Mixed Traffic Stress)**: Mixed destination, random priorities, and full crossbar utilization.

### Verified Waveform Reports
Refer to [`docs/output_router_waveform.pdf`](docs/output_router_waveform.pdf) and [`docs/output_router_waveform_new1.pdf`](docs/output_router_waveform_new1.pdf) for cycle-by-cycle ModelSim waveform traces.

---

## 4. How to Simulate

```bash
# Initialize ModelSim work library
vlib work

# Compile synthesizable RTL
vlog rtl/router_top.v

# Compile and run Scenario 2 (Contention & Arbitration)
vlog tb/TB_S2.v
vsim -c -do "run -all; quit" work.TB_S2

# Compile and run Scenario 3 (Aging & Starvation Prevention)
vlog tb/TB_S3.v
vsim -c -do "run -all; quit" work.TB_S3
```

---

## 5. Repository File Structure

```text
VOQ-2x2-NoC-Router/
├── README.md
├── .gitignore
│
├── rtl/
│   └── router_top.v                      # Production synthesizable RTL top and modular blocks
│
├── tb/
│   ├── TB_S1.v                           # Scenario 1: Basic flow testbench
│   ├── TB_S2.v                           # Scenario 2: Contention & arbitration testbench
│   ├── TB_S3.v                           # Scenario 3: 3-cycle aging testbench
│   ├── TB_S4.v                           # Scenario 4: FIFO burst & backpressure testbench
│   ├── TB_S5.v                           # Scenario 5: CRC parity error testbench
│   └── TB_S6.v                           # Scenario 6: Mixed stress testbench
│
└── docs/
    ├── noc_router_architecture_presentation.pptx  # Hackathon architectural slides
    ├── output_router_waveform.pdf                 # ModelSim simulation waveform report
    └── output_router_waveform_new1.pdf            # Upgraded waveform analysis report
```
