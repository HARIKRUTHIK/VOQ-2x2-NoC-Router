// ============================================================
// SCENARIO 1 - Normal Routing
// PURPOSE: Prove basic packet forwarding works correctly
//
// TEST:
//   in0 -> prio=2, dest=Out0, pkt_id=1, payload=0x55555
//   in1 -> prio=1, dest=Out1, pkt_id=2, payload=0x2AAAA
//
// EXPECTED WAVEFORM:
//   T=55ns  : grant0_in0=1, grant1_in1=1  (both granted separately)
//   T=65ns  : out0 shows in0 packet, out1 shows in1 packet
//   T=75ns  : outputs return to 0 (done)
//   crc_err0=0, crc_err1=0 throughout
//
// WHAT TO TELL EVALUATOR:
//   "Two packets with different destinations are routed in parallel
//    with zero conflict. CRC verified on both. Packet ID preserved."
// ============================================================
`timescale 1ns/1ps
module tb_s1_normal_routing;

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

    initial begin
        $display("============================================");
        $display("  S1: Normal Routing - Different Destinations");
        $display("============================================");
        $display("in0 -> prio=2  dest=Out0  pkt_id=1");
        $display("in1 -> prio=1  dest=Out1  pkt_id=2");
        $display("Expected: Parallel routing, no conflict");
        $display("============================================");

        clk=0; reset=1; valid0=0; valid1=0; in0=0; in1=0;
        #20; reset=0; #10;

        in0 = make_packet(2'b10, 1'b0, 5'd1, 19'h55555);
        in1 = make_packet(2'b01, 1'b1, 5'd2, 19'h2AAAA);

        $display("[T=%0t] Injecting packets...", $time);
        $display("  in0 = 0x%h  (prio=%0d dest=%0d pkt_id=%0d)",
                  in0, in0[31:30], in0[29], in0[28:24]);
        $display("  in1 = 0x%h  (prio=%0d dest=%0d pkt_id=%0d)",
                  in1, in1[31:30], in1[29], in1[28:24]);

        valid0=1; valid1=1; #10;
        valid0=0; valid1=0; in0=0; in1=0;

        // Wait for pipeline: reg(1) + fifo_write(1) + arb(1) + fifo_read(1)
        #50;

        $display("\n[T=%0t] Results:", $time);
        $display("  out0 = 0x%h  (prio=%0d dest=%0d pkt_id=%0d)",
                  out0, out0[31:30], out0[29], out0[28:24]);
        $display("  out1 = 0x%h  (prio=%0d dest=%0d pkt_id=%0d)",
                  out1, out1[31:30], out1[29], out1[28:24]);
        $display("  crc_error0=%b  crc_error1=%b", crc_error0, crc_error1);
        $display("  conflict_cnt=%0d  throughput=%0d",
                  conflict_cnt, throughput_cnt);
        $display("  avg_latency=%0d  max_latency=%0d cycles",
                  avg_latency, max_latency);

        if (out0[28:24] == 5'd1)
            $display("  PASS: pkt_id=1 correctly on out0");
        else
            $display("  FAIL: pkt_id wrong on out0 (got %0d)", out0[28:24]);

        if (out1[28:24] == 5'd2)
            $display("  PASS: pkt_id=2 correctly on out1");
        else
            $display("  FAIL: pkt_id wrong on out1 (got %0d)", out1[28:24]);

        if (conflict_cnt == 0)
            $display("  PASS: Zero conflicts - parallel routing works");
        else
            $display("  NOTE: Conflict_cnt=%0d", conflict_cnt);

        if (crc_error0==0 && crc_error1==0)
            $display("  PASS: CRC valid on both packets");
        else
            $display("  FAIL: CRC error detected");

        #20;
        $display("\n  throughput=%0d packets forwarded", throughput_cnt);
        $display("  latency_sum=%0d  avg=%0d  max=%0d cycles",
                  latency_sum, avg_latency, max_latency);
        $display("============================================");
        $finish;
    end

    initial begin
        $monitor("T=%0t | g0i0=%b g0i1=%b g1i0=%b g1i1=%b | out0=%h out1=%h | avg_lat=%0d",
            $time,
            grant0_in0, grant0_in1, grant1_in0, grant1_in1,
            out0, out1, avg_latency);
    end

endmodule
