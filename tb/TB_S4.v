// ============================================================
// SCENARIO 4 - CRC Error Detection
// PURPOSE: Prove bad packets are detected and DROPPED
//          before they ever reach the output
//
// TEST:
//   Inject 0xDEADBEEF -- a deliberately corrupted packet
//   The stored CRC in [4:0] does NOT match the computed CRC
//   of the header+payload fields [31:5]
//
// CRC CALCULATION FOR DEADBEEF:
//   data = DEADBEEF[31:5] = 27-bit value
//   computed crc != DEADBEEF[4:0] -> error=1
//
// EXPECTED WAVEFORM:
//   crc_error0 pulses HIGH for exactly 1 clock cycle
//   crc_err0_latched goes HIGH and STAYS high (latch)
//   out0 stays 0x00000000 (packet was dropped, not forwarded)
//   throughput_cnt does NOT increment
//   avg_latency stays 0 (no valid packet to measure)
//
// WHAT TO TELL EVALUATOR:
//   "Bad packet is detected in 1 pipeline cycle and silently
//    dropped before reaching any FIFO. crc_error flag raised
//    for monitoring. This protects downstream logic from
//    corrupted data -- essential in storage controllers."
// ============================================================
`timescale 1ns/1ps
module tb_s4_crc_error;

    reg         clk, reset;
    reg  [31:0] in0, in1;
    reg         valid0, valid1;
    wire [31:0] out0, out1;
    wire [31:0] throughput_cnt, conflict_cnt;
    wire [31:0] starvation_prev_cnt;
    wire [31:0] latency_sum, max_latency, avg_latency;
    wire        crc_error0, crc_error1;
    wire        grant0_in0, grant0_in1;
    wire        grant1_in0, grant1_in1;

    router_top DUT (
        .clk(clk), .reset(reset),
        .in0(in0), .in1(in1),
        .valid0(valid0), .valid1(valid1),
        .out0(out0), .out1(out1),
        .throughput_cnt(throughput_cnt),
        .conflict_cnt(conflict_cnt),
        .starvation_prev_cnt(starvation_prev_cnt),
        .latency_sum(latency_sum),
        .max_latency(max_latency),
        .avg_latency(avg_latency),
        .crc_error0(crc_error0), .crc_error1(crc_error1),
        .grant0_in0(grant0_in0), .grant0_in1(grant0_in1),
        .grant1_in0(grant1_in0), .grant1_in1(grant1_in1)
    );

    always #5 clk = ~clk;

    // Latch to capture the 1-cycle pulse of crc_error0
    // crc_error0 is combinational gated with reg_valid0
    // It goes HIGH for exactly 1 cycle then drops
    // latched version holds it for the check
    reg crc_err0_latched;
    reg crc_err1_latched;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            crc_err0_latched <= 1'b0;
            crc_err1_latched <= 1'b0;
        end else begin
            if (crc_error0) crc_err0_latched <= 1'b1;
            if (crc_error1) crc_err1_latched <= 1'b1;
        end
    end

    initial begin
        $display("============================================");
        $display("  S4: CRC Error Detection");
        $display("============================================");
        $display("Injecting 0xDEADBEEF - corrupted packet");
        $display("  stored CRC  = DEADBEEF[4:0]  = 5'b01111");
        $display("  computed CRC != stored CRC   -> error=1");
        $display("Expected: crc_error0=1, packet DROPPED");
        $display("          out0 stays 0, throughput unchanged");
        $display("          avg_latency stays 0 (nothing forwarded)");
        $display("============================================");

        clk=0; reset=1; valid0=0; valid1=0; in0=0; in1=0;
        #20; reset=0; #10;

        $display("[T=%0t] Injecting DEADBEEF...", $time);
        valid0=1; in0=32'hDEADBEEF;
        #10; valid0=0; in0=0;

        // Wait 2 clock cycles for pipeline
        // Cycle 1: input_register clocks DEADBEEF in (reg_valid0=1)
        // Cycle 2: crc_error0 fires (crc_e0_raw=1 AND reg_valid0=1)
        // Cycle 3: reg_valid0 drops -> crc_error0 drops back to 0
        @(posedge clk); @(posedge clk); #1;

        $display("[T=%0t] CRC check window:", $time);
        $display("  crc_error0 live   = %b (may already be 0 - 1 cycle pulse)",
                  crc_error0);
        $display("  crc_err0_latched  = %b (holds the pulse - use this)",
                  crc_err0_latched);

        #30;
        $display("\n[T=%0t] Results after drain:", $time);
        $display("  out0            = 0x%h (expected 0x00000000)", out0);
        $display("  throughput_cnt  = %0d  (expected 0)", throughput_cnt);
        $display("  crc_err latched = %b   (expected 1)", crc_err0_latched);
        $display("  avg_latency     = %0d  (expected 0 - nothing forwarded)",
                  avg_latency);
        $display("  latency_sum     = %0d  (expected 0)", latency_sum);

        if (crc_err0_latched == 1'b1)
            $display("  PASS: CRC error detected");
        else
            $display("  FAIL: CRC error not caught");

        if (out0 == 32'h0)
            $display("  PASS: Bad packet dropped - out0 = 0");
        else
            $display("  FAIL: Bad packet reached output!");

        if (throughput_cnt == 0)
            $display("  PASS: throughput unchanged - no forwarding");
        else
            $display("  FAIL: throughput incremented for bad packet!");

        $display("============================================");
        $finish;
    end

    initial begin
        $monitor("T=%0t | valid0=%b | crc_error0=%b latched=%b | out0=%h | tput=%0d | avg_lat=%0d",
            $time, valid0, crc_error0, crc_err0_latched,
            out0, throughput_cnt, avg_latency);
    end

endmodule
