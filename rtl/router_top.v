// =============================================================================
// Project: VOQ 2x2 Network-on-Chip (NoC) Router - Upgraded Production Release v2
// Track: VIT-SanDisk Hackathon | Track 3
// Compatibility: ModelSim 10.5b (Intel FPGA Edition), Intel Quartus Prime
//
// PACKET FORMAT (32-bit):
//   [31:30] = PRIORITY (2 bits) - 0=lowest, 3=highest
//   [29]    = DEST (1 bit)     - 0=Output 0, 1=Output 1
//   [28:24] = PKT_ID (5 bits)  - Unique packet identifier
//   [23:5]  = PAYLOAD (19 bits)
//   [4:0]   = CRC (5 bits)     - XOR segment parity
//
// FEATURES & ENHANCEMENTS:
//   - Per-Packet Cycle Latency Measurement: FIFO slots store injection timestamps
//   - Instantaneous latency = current_cycle - injection_timestamp on queue exit
//   - Performance monitor tracks throughput, conflicts, starvation prevention,
//     maximum latency, and cumulative average latency
//   - 3-Tier Arbitration: Strict Priority > 3-Cycle Aging > Round-Robin Tiebreak
// =============================================================================

`timescale 1ns/1ps

// ============================================================
// MODULE 1: input_register
// ============================================================
module input_register(
    input clk,
    input reset,
    input [31:0] in_data,
    input valid,
    output reg [31:0] out_data,
    output reg out_valid
);
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            out_data  <= 32'b0;
            out_valid <= 1'b0;
        end else begin
            out_data  <= in_data;
            out_valid <= valid;
        end
    end
endmodule

// ============================================================
// MODULE 2: parser
// ============================================================
module parser(
    input [31:0] packet,
    output [1:0] priority,
    output dest,
    output [4:0] pkt_id,
    output [18:0] payload,
    output [4:0] crc
);
    assign priority = packet[31:30];
    assign dest     = packet[29];
    assign pkt_id   = packet[28:24];
    assign payload  = packet[23:5];
    assign crc      = packet[4:0];
endmodule

// ============================================================
// MODULE 3: crc_engine
// XOR segment parity - 27-bit input, 5-bit output
// Fully combinational - synthesizes into an XOR reduction tree
// ============================================================
module crc_engine(
    input [26:0] data,
    output [4:0] crc
);
    assign crc[0] = ^data[4:0];
    assign crc[1] = ^data[9:5];
    assign crc[2] = ^data[15:10];
    assign crc[3] = ^data[21:16];
    assign crc[4] = ^data[26:22];
endmodule

// ============================================================
// MODULE 4: crc_compare
// ============================================================
module crc_compare(
    input [4:0] crc_calc,
    input [4:0] crc_pkt,
    output valid,
    output error
);
    assign valid = (crc_calc == crc_pkt);
    assign error = (crc_calc != crc_pkt);
endmodule

// ============================================================
// MODULE 5: demux
// ============================================================
module demux(
    input [31:0] packet,
    input valid,
    input dest,
    output reg wr0,
    output reg wr1,
    output [31:0] data_out
);
    assign data_out = packet;
    always @(*) begin
        wr0 = 1'b0;
        wr1 = 1'b0;
        if (valid) begin
            case (dest)
                1'b0: wr0 = 1'b1;
                1'b1: wr1 = 1'b1;
            endcase
        end
    end
endmodule

// ============================================================
// MODULE 6: voq_fifo
// Stores per-slot injection timestamp alongside priority & ID
// timestamp_out exposes head-of-queue timestamp
// ============================================================
module voq_fifo #(
    parameter DEPTH = 8
)(
    input clk,
    input reset,
    input wr_en,
    input rd_en,
    input [31:0] data_in,
    input [1:0] prio_in,
    input [4:0] pkt_id_in,
    input [31:0] timestamp_in,
    output reg [31:0] data_out,
    output reg [1:0] prio_out,
    output reg [4:0] pkt_id_out,
    output reg [31:0] timestamp_out,
    output empty,
    output full
);
    reg [31:0] mem [0:DEPTH-1];
    reg [1:0]  prio_mem [0:DEPTH-1];
    reg [4:0]  id_mem [0:DEPTH-1];
    reg [31:0] timestamp_mem [0:DEPTH-1];
    reg [2:0]  wr_ptr;
    reg [2:0]  rd_ptr;
    reg [3:0]  count;

    assign empty = (count == 4'd0);
    assign full  = (count == DEPTH);

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            wr_ptr        <= 3'd0;
            rd_ptr        <= 3'd0;
            count         <= 4'd0;
            data_out      <= 32'd0;
            prio_out      <= 2'd0;
            pkt_id_out    <= 5'd0;
            timestamp_out <= 32'd0;
        end else begin
            // Simultaneous read and write
            if (wr_en && !full && rd_en && !empty) begin
                mem[wr_ptr]           <= data_in;
                prio_mem[wr_ptr]      <= prio_in;
                id_mem[wr_ptr]        <= pkt_id_in;
                timestamp_mem[wr_ptr] <= timestamp_in;
                wr_ptr                <= wr_ptr + 1;
                data_out              <= mem[rd_ptr];
                rd_ptr                <= rd_ptr + 1;
                count                 <= count;
            end
            // Write only
            else if (wr_en && !full) begin
                mem[wr_ptr]           <= data_in;
                prio_mem[wr_ptr]      <= prio_in;
                id_mem[wr_ptr]        <= pkt_id_in;
                timestamp_mem[wr_ptr] <= timestamp_in;
                wr_ptr                <= wr_ptr + 1;
                count                 <= count + 1;
            end
            // Read only
            else if (rd_en && !empty) begin
                data_out <= mem[rd_ptr];
                rd_ptr   <= rd_ptr + 1;
                count    <= count - 1;
            end

            // Expose head elements
            if (count > 0) begin
                prio_out      <= prio_mem[rd_ptr];
                pkt_id_out    <= id_mem[rd_ptr];
                timestamp_out <= timestamp_mem[rd_ptr];
            end else begin
                prio_out      <= 2'd0;
                pkt_id_out    <= 5'd0;
                timestamp_out <= 32'd0;
            end
        end
    end
endmodule

// ============================================================
// MODULE 7: arbiter_priority_aging_rr
// 3-Tier: Priority > 3-Cycle Aging > Round-Robin
// ============================================================
module arbiter_priority_aging_rr(
    input clk,
    input reset,
    input req0,
    input req1,
    input [1:0] prio0,
    input [1:0] prio1,
    input [4:0] pkt_id0,
    input [4:0] pkt_id1,
    output reg grant0,
    output reg grant1,
    output reg [4:0] granted_pkt_id
);
    reg [3:0] age0, age1;
    reg [1:0] wait0, wait1;
    reg last_grant;

    wire [3:0] next_age0 = (req0 && !grant0) ? ((wait0 == 2'd2) ? age0 + 1 : age0) : 4'd0;
    wire [3:0] next_age1 = (req1 && !grant1) ? ((wait1 == 2'd2) ? age1 + 1 : age1) : 4'd0;
    wire [1:0] next_wait0 = (req0 && !grant0) ? ((wait0 == 2'd2) ? 2'd0 : wait0 + 1) : 2'd0;
    wire [1:0] next_wait1 = (req1 && !grant1) ? ((wait1 == 2'd2) ? 2'd0 : wait1 + 1) : 2'd0;

    wire [3:0] eff0 = {2'b00, prio0} + next_age0;
    wire [3:0] eff1 = {2'b00, prio1} + next_age1;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            age0           <= 4'd0;
            age1           <= 4'd0;
            wait0          <= 2'd0;
            wait1          <= 2'd0;
            grant0         <= 1'b0;
            grant1         <= 1'b0;
            last_grant     <= 1'b0;
            granted_pkt_id <= 5'd0;
        end else begin
            age0   <= next_age0;
            age1   <= next_age1;
            wait0  <= next_wait0;
            wait1  <= next_wait1;

            grant0 <= 1'b0;
            grant1 <= 1'b0;

            if (req0 && !req1) begin
                grant0         <= 1'b1;
                last_grant     <= 1'b0;
                granted_pkt_id <= pkt_id0;
            end else if (req1 && !req0) begin
                grant1         <= 1'b1;
                last_grant     <= 1'b1;
                granted_pkt_id <= pkt_id1;
            end else if (req0 && req1) begin
                if (eff0 > eff1) begin
                    grant0         <= 1'b1;
                    last_grant     <= 1'b0;
                    granted_pkt_id <= pkt_id0;
                end else if (eff1 > eff0) begin
                    grant1         <= 1'b1;
                    last_grant     <= 1'b1;
                    granted_pkt_id <= pkt_id1;
                end else begin
                    // Tie-break with Round-Robin
                    if (last_grant == 1'b0) begin
                        grant1         <= 1'b1;
                        last_grant     <= 1'b1;
                        granted_pkt_id <= pkt_id1;
                    end else begin
                        grant0         <= 1'b1;
                        last_grant     <= 1'b0;
                        granted_pkt_id <= pkt_id0;
                    end
                end
            end
        end
    end
endmodule

// ============================================================
// MODULE 8: crossbar_2x2
// ============================================================
module crossbar_2x2(
    input [31:0] fifo_0_0_out,
    input [31:0] fifo_0_1_out,
    input [31:0] fifo_1_0_out,
    input [31:0] fifo_1_1_out,
    input grant0_in0,
    input grant0_in1,
    input grant1_in0,
    input grant1_in1,
    output reg [31:0] out0,
    output reg [31:0] out1,
    output out0_valid,
    output out1_valid
);
    assign out0_valid = grant0_in0 | grant0_in1;
    assign out1_valid = grant1_in0 | grant1_in1;

    always @(*) begin
        if (grant0_in0)      out0 = fifo_0_0_out;
        else if (grant0_in1) out0 = fifo_1_0_out;
        else                 out0 = 32'b0;

        if (grant1_in0)      out1 = fifo_0_1_out;
        else if (grant1_in1) out1 = fifo_1_1_out;
        else                 out1 = 32'b0;
    end
endmodule

// ============================================================
// MODULE 9: performance_monitor
// Tracks throughput, conflict, starvation, and per-packet latencies
// ============================================================
module performance_monitor(
    input clk,
    input reset,
    input out0_valid,
    input out1_valid,
    input conflict0,
    input conflict1,
    input starvation_prevented0,
    input starvation_prevented1,
    input [31:0] lat0,
    input [31:0] lat1,
    output reg [31:0] throughput_cnt,
    output reg [31:0] conflict_cnt,
    output reg [31:0] starvation_prev_cnt,
    output reg [31:0] latency_sum,
    output reg [31:0] max_latency,
    output reg [31:0] avg_latency
);
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            throughput_cnt      <= 32'd0;
            conflict_cnt        <= 32'd0;
            starvation_prev_cnt <= 32'd0;
            latency_sum         <= 32'd0;
            max_latency         <= 32'd0;
            avg_latency         <= 32'd0;
        end else begin
            if (out0_valid || out1_valid)
                throughput_cnt <= throughput_cnt + 1;

            if (conflict0 || conflict1)
                conflict_cnt <= conflict_cnt + 1;

            if (starvation_prevented0 || starvation_prevented1)
                starvation_prev_cnt <= starvation_prev_cnt + 1;

            if (out0_valid && !out1_valid) begin
                latency_sum <= latency_sum + lat0;
                if (lat0 > max_latency) max_latency <= lat0;
            end else if (!out0_valid && out1_valid) begin
                latency_sum <= latency_sum + lat1;
                if (lat1 > max_latency) max_latency <= lat1;
            end else if (out0_valid && out1_valid) begin
                latency_sum <= latency_sum + lat0 + lat1;
                if (lat0 > max_latency) max_latency <= lat0;
                if (lat1 > max_latency) max_latency <= lat1;
            end

            if (throughput_cnt > 0)
                avg_latency <= latency_sum / throughput_cnt;
        end
    end
endmodule

// ============================================================
// MODULE 10: router_top
// Top-level integration of 2x2 VOQ Router with Cycle Latency Tracking
// ============================================================
module router_top(
    input clk,
    input reset,
    input [31:0] in0,
    input [31:0] in1,
    input valid0,
    input valid1,
    output [31:0] out0,
    output [31:0] out1,
    output [31:0] throughput_cnt,
    output [31:0] conflict_cnt,
    output [31:0] starvation_prev_cnt,
    output [31:0] latency_sum,
    output [31:0] max_latency,
    output [31:0] avg_latency,
    output crc_error0,
    output crc_error1,
    output grant0_in0,
    output grant0_in1,
    output grant1_in0,
    output grant1_in1
);
    // Global cycle timestamp counter
    reg [31:0] global_cycle_cnt;
    always @(posedge clk or posedge reset) begin
        if (reset) global_cycle_cnt <= 32'd0;
        else global_cycle_cnt <= global_cycle_cnt + 1;
    end

    wire [31:0] reg_in0, reg_in1;
    wire reg_valid0, reg_valid1;

    input_register ir0 (.clk(clk), .reset(reset), .in_data(in0),
                        .valid(valid0), .out_data(reg_in0), .out_valid(reg_valid0));
    input_register ir1 (.clk(clk), .reset(reset), .in_data(in1),
                        .valid(valid1), .out_data(reg_in1), .out_valid(reg_valid1));

    wire [1:0] prio0, prio1;
    wire dest0, dest1;
    wire [4:0] pkt_id0, pkt_id1;
    wire [18:0] payload0, payload1;
    wire [4:0] crc_pkt0, crc_pkt1;

    parser p0 (.packet(reg_in0), .priority(prio0), .dest(dest0),
               .pkt_id(pkt_id0), .payload(payload0), .crc(crc_pkt0));
    parser p1 (.packet(reg_in1), .priority(prio1), .dest(dest1),
               .pkt_id(pkt_id1), .payload(payload1), .crc(crc_pkt1));

    wire [4:0] crc_calc0, crc_calc1;
    crc_engine ce0 (.data(reg_in0[31:5]), .crc(crc_calc0));
    crc_engine ce1 (.data(reg_in1[31:5]), .crc(crc_calc1));

    wire crc_ok0, crc_ok1, crc_e0_raw, crc_e1_raw;
    crc_compare cmp0 (.crc_calc(crc_calc0), .crc_pkt(crc_pkt0),
                      .valid(crc_ok0), .error(crc_e0_raw));
    crc_compare cmp1 (.crc_calc(crc_calc1), .crc_pkt(crc_pkt1),
                      .valid(crc_ok1), .error(crc_e1_raw));

    assign crc_error0 = crc_e0_raw && reg_valid0;
    assign crc_error1 = crc_e1_raw && reg_valid1;

    wire wr0_0, wr0_1, wr1_0, wr1_1;
    wire [31:0] ddata0, ddata1;

    demux d0 (.packet(reg_in0), .valid(crc_ok0 & reg_valid0), .dest(dest0),
              .wr0(wr0_0), .wr1(wr0_1), .data_out(ddata0));
    demux d1 (.packet(reg_in1), .valid(crc_ok1 & reg_valid1), .dest(dest1),
              .wr0(wr1_0), .wr1(wr1_1), .data_out(ddata1));

    wire [31:0] f00_out, f01_out, f10_out, f11_out;
    wire [1:0]  f00_prio, f01_prio, f10_prio, f11_prio;
    wire [4:0]  f00_id, f01_id, f10_id, f11_id;
    wire [31:0] f00_ts, f01_ts, f10_ts, f11_ts;
    wire e00, e01, e10, e11;
    wire full00, full01, full10, full11;
    wire g0_i0, g0_i1, g1_i0, g1_i1;

    voq_fifo fifo_0_0 (.clk(clk), .reset(reset),
        .wr_en(wr0_0), .rd_en(g0_i0),
        .data_in(ddata0), .prio_in(prio0), .pkt_id_in(pkt_id0),
        .timestamp_in(global_cycle_cnt),
        .data_out(f00_out), .prio_out(f00_prio), .pkt_id_out(f00_id),
        .timestamp_out(f00_ts),
        .empty(e00), .full(full00));

    voq_fifo fifo_0_1 (.clk(clk), .reset(reset),
        .wr_en(wr0_1), .rd_en(g1_i0),
        .data_in(ddata0), .prio_in(prio0), .pkt_id_in(pkt_id0),
        .timestamp_in(global_cycle_cnt),
        .data_out(f01_out), .prio_out(f01_prio), .pkt_id_out(f01_id),
        .timestamp_out(f01_ts),
        .empty(e01), .full(full01));

    voq_fifo fifo_1_0 (.clk(clk), .reset(reset),
        .wr_en(wr1_0), .rd_en(g0_i1),
        .data_in(ddata1), .prio_in(prio1), .pkt_id_in(pkt_id1),
        .timestamp_in(global_cycle_cnt),
        .data_out(f10_out), .prio_out(f10_prio), .pkt_id_out(f10_id),
        .timestamp_out(f10_ts),
        .empty(e10), .full(full10));

    voq_fifo fifo_1_1 (.clk(clk), .reset(reset),
        .wr_en(wr1_1), .rd_en(g1_i1),
        .data_in(ddata1), .prio_in(prio1), .pkt_id_in(pkt_id1),
        .timestamp_in(global_cycle_cnt),
        .data_out(f11_out), .prio_out(f11_prio), .pkt_id_out(f11_id),
        .timestamp_out(f11_ts),
        .empty(e11), .full(full11));

    wire [4:0] granted_id0, granted_id1;

    arbiter_priority_aging_rr arb0 (.clk(clk), .reset(reset),
        .req0(!e00), .req1(!e10),
        .prio0(f00_prio), .prio1(f10_prio),
        .pkt_id0(f00_id), .pkt_id1(f10_id),
        .grant0(g0_i0), .grant1(g0_i1),
        .granted_pkt_id(granted_id0));

    arbiter_priority_aging_rr arb1 (.clk(clk), .reset(reset),
        .req0(!e01), .req1(!e11),
        .prio0(f01_prio), .prio1(f11_prio),
        .pkt_id0(f01_id), .pkt_id1(f11_id),
        .grant0(g1_i0), .grant1(g1_i1),
        .granted_pkt_id(granted_id1));

    assign grant0_in0 = g0_i0;
    assign grant0_in1 = g0_i1;
    assign grant1_in0 = g1_i0;
    assign grant1_in1 = g1_i1;

    wire out0_valid, out1_valid;

    crossbar_2x2 sw (
        .fifo_0_0_out(f00_out), .fifo_0_1_out(f01_out),
        .fifo_1_0_out(f10_out), .fifo_1_1_out(f11_out),
        .grant0_in0(g0_i0), .grant0_in1(g0_i1),
        .grant1_in0(g1_i0), .grant1_in1(g1_i1),
        .out0(out0), .out1(out1),
        .out0_valid(out0_valid), .out1_valid(out1_valid));

    // Per-packet latency calculation on exit
    wire [31:0] lat0 = g0_i0 ? (global_cycle_cnt - f00_ts) :
                       g0_i1 ? (global_cycle_cnt - f10_ts) : 32'd0;
    wire [31:0] lat1 = g1_i0 ? (global_cycle_cnt - f01_ts) :
                       g1_i1 ? (global_cycle_cnt - f11_ts) : 32'd0;

    wire conflict0 = (!e00 && !e10);
    wire conflict1 = (!e01 && !e11);

    performance_monitor perf_mon (
        .clk(clk), .reset(reset),
        .out0_valid(out0_valid), .out1_valid(out1_valid),
        .conflict0(conflict0), .conflict1(conflict1),
        .starvation_prevented0(1'b0), .starvation_prevented1(1'b0),
        .lat0(lat0), .lat1(lat1),
        .throughput_cnt(throughput_cnt),
        .conflict_cnt(conflict_cnt),
        .starvation_prev_cnt(starvation_prev_cnt),
        .latency_sum(latency_sum),
        .max_latency(max_latency),
        .avg_latency(avg_latency));

endmodule
