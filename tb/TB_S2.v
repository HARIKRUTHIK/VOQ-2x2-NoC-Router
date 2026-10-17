// ============================================================
// SCENARIO 2 - Congestion / Priority Arbitration (FIXED v2)
//
// ROOT CAUSE OF MISSING SECOND PACKET:
//   voq_fifo has 1-cycle registered read latency.
//   When grant fires (rd_en=1), data_out updates NEXT cycle.
//   For pkt_id=3 this is fine (it was head-of-queue already).
//   For pkt_id=4: after pkt_id=3 drains, FIFO_1_0 needs 1 extra
//   cycle to expose pkt_id=4 on data_out before crossbar reads it.
//
// FIX IN TB:
//   Wait longer (#300 instead of #200) and capture second packet
//   using a 1-cycle delayed version of grant signal so we catch
//   the actual data that appears on out0 one cycle after grant.
//
// NOTE: Router_top NOT modified. TB-only fix.
// ============================================================
`timescale 1ns/1ps
module tb_s2_congestion;

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

    // --------------------------------------------------------
    // KEY FIX: 1-cycle delayed grant capture
    // voq_fifo data_out is registered ? updates 1 cycle AFTER rd_en
    // So out0 shows the packet 1 cycle AFTER grant fires
    // We capture on the cycle AFTER grant to get real pkt_id
    // --------------------------------------------------------
    reg grant0_in0_d, grant0_in1_d;
    always @(posedge clk) begin
        grant0_in0_d <= grant0_in0;
        grant0_in1_d <= grant0_in1;
    end

    // Capture window: grant fired THIS or LAST cycle ? out0 is valid
    wire out0_capture = grant0_in0 | grant0_in1 | grant0_in0_d | grant0_in1_d;

    reg [4:0] first_out_id;
    reg [4:0] second_out_id;
    reg       first_captured;
    reg       second_captured;

    always @(posedge clk) begin
        if (reset) begin
            first_captured  <= 0;
            second_captured <= 0;
            first_out_id    <= 0;
            second_out_id   <= 0;
        end else if (out0_capture && out0 != 32'b0) begin
            if (!first_captured) begin
                first_out_id   <= out0[28:24];
                first_captured <= 1;
                $display("[T=%0t] >>> FIRST  exits out0: pkt_id=%0d  prio=%0d",
                          $time, out0[28:24], out0[31:30]);
            end else if (!second_captured && out0[28:24] != first_out_id) begin
                second_out_id   <= out0[28:24];
                second_captured <= 1;
                $display("[T=%0t] >>> SECOND exits out0: pkt_id=%0d  prio=%0d",
                          $time, out0[28:24], out0[31:30]);
            end
        end
    end

    initial begin
        $display("============================================");
        $display("  S2: Congestion - Priority Arbitration");
        $display("============================================");
        $display("in0 -> prio=3 HIGH  dest=Out0  pkt_id=3");
        $display("in1 -> prio=1 LOW   dest=Out0  pkt_id=4");
        $display("BOTH want Out0 -> CONFLICT");
        $display("Expected: pkt_id=3 first, pkt_id=4 second");
        $display("============================================");

        clk=0; reset=1; valid0=0; valid1=0; in0=0; in1=0;
        #20; reset=0; #10;

        // Inject both simultaneously ? same clock cycle
        in0 = make_packet(2'b11, 1'b0, 5'd3, 19'h7FFFF);  // prio=3
        in1 = make_packet(2'b01, 1'b0, 5'd4, 19'h08888);  // prio=1

        $display("[T=%0t] Injecting...", $time);
        $display("  in0=0x%h prio=%0d pkt_id=%0d", in0, in0[31:30], in0[28:24]);
        $display("  in1=0x%h prio=%0d pkt_id=%0d", in1, in1[31:30], in1[28:24]);

        valid0=1; valid1=1; #10;
        valid0=0; valid1=0;
        in0=0; in1=0;

        // Wait for pipeline:
        //   Stage1 (reg):        +1 cycle
        //   Stage2 (FIFO write): +1 cycle  ? both packets in FIFO
        //   Stage3 (arb grant):  +1 cycle  ? pkt3 granted, pkt4 waits
        //   pkt3 exits:          cycle 3
        //   pkt4 granted:        cycle 4   (arb sees FIFO_1_0 non-empty)
        //   pkt4 data_out ready: cycle 5   (1-cycle FIFO read latency)
        //   Total for both:      ~10 cycles = 100ns minimum
        //   Wait 300ns for comfortable margin
        #300;

        $display("\n[T=%0t] ===== RESULTS =====", $time);
        $display("  conflict_cnt   = %0d  (expected >= 1)", conflict_cnt);
        $display("  throughput_cnt = %0d  (expected >= 2)", throughput_cnt);
        $display("  first_pkt_id   = %0d  (expected = 3)", first_out_id);
        $display("  second_pkt_id  = %0d  (expected = 4)", second_out_id);
        $display("  avg_latency    = %0d cycles", avg_latency);
        $display("  max_latency    = %0d cycles", max_latency);

        $display("\n  --- CHECKS ---");

        if (conflict_cnt >= 1)
            $display("  PASS: conflict_cnt=%0d ? arbiter saw both FIFOs non-empty", conflict_cnt);
        else
            $display("  FAIL: No conflict detected");

        if (first_out_id == 5'd3)
            $display("  PASS: pkt_id=3 (prio=3) exited FIRST ? priority works");
        else
            $display("  FAIL: wrong first packet (got pkt_id=%0d)", first_out_id);

        if (second_captured && second_out_id == 5'd4)
            $display("  PASS: pkt_id=4 (prio=1) exited SECOND ? low prio served");
        else if (!second_captured)
            $display("  FAIL: pkt_id=4 never exited ? FIFO_1_0 stuck");
        else
            $display("  FAIL: wrong second packet (got pkt_id=%0d)", second_out_id);

        if (throughput_cnt >= 2)
            $display("  PASS: throughput >= 2 ? no packet dropped");
        else
            $display("  FAIL: throughput=%0d, packet lost", throughput_cnt);

        $display("============================================");
        $finish;
    end

    initial begin
        $monitor("T=%0t | g0i0=%b g0i1=%b | g0i0_d=%b g0i1_d=%b | out0=%h pkt_id=%0d | conflict=%0d tput=%0d avg_lat=%0d",
            $time,
            grant0_in0, grant0_in1,
            grant0_in0_d, grant0_in1_d,
            out0, out0[28:24],
            conflict_cnt, throughput_cnt, avg_latency);
    end

endmodule
