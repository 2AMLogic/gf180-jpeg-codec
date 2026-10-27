// jc_dct: DCT stage (decision records 0003 and 0005). Level shift, row pass,
// column pass of the record 0003 integer DCT over one `jc_dct1d` engine and
// the 64 x 14 `jc_xpose_rf` transpose file.
//
// S3 in (0005 section 4): one 32-bit M0 word per beat, lane k = column
// (4 * half + k), word 0 of a row = columns 0..3, word 1 = columns 4..7;
// 16 words per block, rows in order. Tag {last, comp[1:0], first}:
// `comp` and `last` are read from the second word of each row (`last` is
// meaningful on the block's final word, set only for the frame's last block);
// `first` is accepted but unused, the stage counts words itself.
// S4 out: {natural_idx[5:0], coef[14:0]}, column by column, 8 per column,
// idx = 8 * vertical + horizontal frequency. Tag {last, comp[1:0]}; `last` is
// on the final coefficient (idx 63) of the frame's last block only.
// Valid/ready on both streams, synchronous active-low reset.
module jc_dct (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        s3_valid,
    output wire        s3_ready,
    input  wire [31:0] s3_data,
    /* verilator lint_off UNUSEDSIGNAL */  // bit 0 is not consumed by this stage
    input  wire [3:0]  s3_tag,
    /* verilator lint_on UNUSEDSIGNAL */

    output wire        s4_valid,
    input  wire        s4_ready,
    output wire [20:0] s4_data,
    output wire [2:0]  s4_tag
);
    // ---- S3 row assembly buffer ----------------------------------------
    reg [31:0] lo, hi;
    reg        have_lo, buf_full;
    reg [1:0]  buf_comp;
    reg        buf_last;

    assign s3_ready = rst_n && !buf_full;
    wire s3_fire = s3_valid && s3_ready;

    // ---- control -------------------------------------------------------
    reg        phase2;           // 0: row pass collecting, 1: column pass
    reg [2:0]  cnt;              // next row / column to start
    reg [2:0]  eng_idx;          // row / column in the engine
    reg        eng_p2;
    reg [1:0]  cur_comp;
    reg        cur_last;

    wire        busy, done;
    wire [119:0] o_flat;
    wire [111:0] xp_rdata;

    reg         emit_valid;
    reg [2:0]   emit_cnt;
    reg [2:0]   emit_col;
    reg [1:0]   emit_comp;
    reg         emit_last;
    reg [119:0] out_o;

    wire s4_fire = s4_valid && s4_ready;
    wire out_free = !emit_valid || (s4_fire && emit_cnt == 3'd7);

    wire start = !busy && (phase2 || buf_full);

    // Level shift: sample - 128 flips the MSB; sign-extend to 14 bits.
    // Each lane is {6{~s[7]}, ~s[7], s[6:0]}: the shifted sample, sign-extended.
    wire [111:0] row_flat = {
        {{6{~hi[31]}}, ~hi[31], hi[30:24]}, {{6{~hi[23]}}, ~hi[23], hi[22:16]},
        {{6{~hi[15]}}, ~hi[15], hi[14:8]},  {{6{~hi[7]}},  ~hi[7],  hi[6:0]},
        {{6{~lo[31]}}, ~lo[31], lo[30:24]}, {{6{~lo[23]}}, ~lo[23], lo[22:16]},
        {{6{~lo[15]}}, ~lo[15], lo[14:8]},  {{6{~lo[7]}},  ~lo[7],  lo[6:0]}
    };

    jc_xpose_rf u_rf (
        .clk(clk),
        .we(done && !eng_p2),
        .wrow(eng_idx),
        .wdata({o_flat[105 +: 14], o_flat[90 +: 14], o_flat[75 +: 14], o_flat[60 +: 14],
                o_flat[45 +: 14],  o_flat[30 +: 14], o_flat[15 +: 14], o_flat[0 +: 14]}),
        .rcol(cnt),
        .rdata(xp_rdata)
    );

    jc_dct1d u_eng (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .pass2(phase2),
        .d_flat(phase2 ? xp_rdata : row_flat),
        .go(eng_p2 ? out_free : 1'b1),
        .busy(busy),
        .done(done),
        .o_flat(o_flat)
    );

    always @(posedge clk) begin
        if (s3_fire) begin
            buf_comp <= s3_tag[2:1];
            buf_last <= s3_tag[3];
            if (!have_lo) lo <= s3_data;
            else          hi <= s3_data;
        end
        if (done && eng_p2) begin
            out_o     <= o_flat;
            emit_col  <= eng_idx;
            emit_comp <= cur_comp;
            emit_last <= cur_last;
        end
        if (start && !phase2) begin
            cur_comp <= buf_comp;
            cur_last <= buf_last;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            have_lo    <= 1'b0;
            buf_full   <= 1'b0;
            phase2     <= 1'b0;
            cnt        <= 3'd0;
            eng_idx    <= 3'd0;
            eng_p2     <= 1'b0;
            emit_valid <= 1'b0;
            emit_cnt   <= 3'd0;
        end else begin
            if (s3_fire) begin
                if (!have_lo) have_lo <= 1'b1;
                else begin
                    have_lo  <= 1'b0;
                    buf_full <= 1'b1;
                end
            end
            if (start) begin
                eng_idx <= cnt;
                eng_p2  <= phase2;
                cnt     <= cnt + 3'd1;
                if (!phase2) buf_full <= 1'b0;
                if (phase2 && cnt == 3'd7) phase2 <= 1'b0;   // after the last column
            end
            if (done && !eng_p2 && eng_idx == 3'd7)
                phase2 <= 1'b1;
            if (s4_fire) begin
                emit_cnt <= emit_cnt + 3'd1;
                if (emit_cnt == 3'd7) emit_valid <= 1'b0;
            end
            if (done && eng_p2) begin
                emit_valid <= 1'b1;
                emit_cnt   <= 3'd0;
            end
        end
    end

    assign s4_valid = emit_valid;
    assign s4_data  = {emit_cnt, emit_col, out_o[15 * emit_cnt +: 15]};
    assign s4_tag   = {emit_last && emit_cnt == 3'd7 && emit_col == 3'd7, emit_comp};
endmodule
