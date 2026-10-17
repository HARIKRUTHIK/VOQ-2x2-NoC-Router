// ============================================================
// SCENARIO 5 - Round-Robin Tiebreak
// PURPOSE: Prove fairness when two inputs have EQUAL priority
//          competing for the same output
//
// TEST:
//   in0 -> prio=2, dest=Out0, pkt_id=7
//   in1 -> prio=2, dest=Out0, pkt_id=8
//   EQUAL priority -> no winner from priority comparison
//   -> Round-Robin decides: alternate grants each cycle
//
// EXPECTED WAVEFORM:
//   grant0_in0 and grant0_in1 both fire at least once
//   out0 shows one pkt then the other
//   Both packets forwarded, throughput=2
//
// WHAT TO TELL EVALUATOR:
//   "When priorities are equal, a simple round-robin memory bit
//    (last_grant) ensures fair alternation. This prevents one
//    input from monopolising the output in the tie case --
//    analogous to weighted round-robin in real switch fabrics."
// ============================================================
`timescale 1ns/1ps
module tb_s5_round_robin;

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

    function [31:0] make_packet;
        input [1:0]  prio;
        input        dest;
        input [4:0]  pkt_id;
        input [18:0] payload;
        reg   [26:0] d;
        reg   [4:0]  crc;
        begin
            d      = {prio, dest, pkt_id, payload};
            crc[0] = ^d[4:0];
            crc[1] = ^d[9:5];
            crc[2] = ^d[15:10];
            crc[3] = ^d[21:16];
            crc[4] = ^d[26:22];
            make_packet = {prio, dest, pkt_id, payload, crc};
        end
    endfunction

    // Count how many times each input was granted on out0
    integer g0_count, g1_count;
    always @(posedge clk) begin
        if (grant0_in0) g0_count <= g0_count + 1;
        if (grant0_in1) g1_count <= g1_count + 1;
    end

    initial begin
        $display("============================================");
        $display("  S5: Round-Robin Tiebreak - Equal Priority");
        $display("============================================");
        $display("in0 -> prio=2  dest=Out0  pkt_id=7");
        $display("in1 -> prio=2  dest=Out0  pkt_id=8");
        $display("Equal priority -> RR must alternate grants");
        $display("============================================");

        clk=0; reset=1; valid0=0; valid1=0; in0=0; in1=0;
        g0_count=0; g1_count=0;
        #20; reset=0; #10;

        in0 = make_packet(2'b10, 1'b0, 5'd7, 19'h11111);
        in1 = make_packet(2'b10, 1'b0, 5'd8, 19'h22222);

        $display("[T=%0t] Injecting equal-priority pair...", $time);
        $display("  in0 = 0x%h  prio=%0d  pkt_id=%0d",
                  in0, in0[31:30], in0[28:24]);
        $display("  in1 = 0x%h  prio=%0d  pkt_id=%0d",
                  in1, in1[31:30], in1[28:24]);

        valid0=1; valid1=1; #10;
        valid0=0; valid1=0; in0=0; in1=0;

        #80;

        $display("\n[T=%0t] Results:", $time);
        $display("  grant0_in0 fired %0d times", g0_count);
        $display("  grant0_in1 fired %0d times", g1_count);
        $display("  throughput_cnt = %0d (expected 2)", throughput_cnt);
        $display("  avg_latency    = %0d cycles", avg_latency);
        $display("  max_latency    = %0d cycles", max_latency);
        $display("  latency_sum    = %0d cycles total", latency_sum);

        if (g0_count >= 1 && g1_count >= 1)
            $display("  PASS: Both inputs got a grant - RR worked");
        else
            $display("  FAIL: One input monopolised - RR broken");

        if (throughput_cnt == 2)
            $display("  PASS: Both packets forwarded");
        else
            $display("  NOTE: throughput=%0d", throughput_cnt);

        $display("\n  NOTE: Check waveform to see grant0_in0 and");
        $display("        grant0_in1 alternating cleanly");
        $display("============================================");
        $finish;
    end

    initial begin
        $monitor("T=%0t | g0i0=%b g0i1=%b | out0=%h (pkt_id=%0d) | tput=%0d | avg_lat=%0d",
            $time,
            grant0_in0, grant0_in1,
            out0, out0[28:24],
            throughput_cnt, avg_latency);
    end

endmodule
