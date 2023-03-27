module ps2 (inout ps2_clk,
            inout ps2_dat,
            input rst_n,
            input clk,
            output[15:0] out);
    
    localparam start_state  = 1;
    localparam data_state   = 2;
    localparam parity_state = 3;
    localparam end_state    = 4;
    
    reg [3:0] state_next, state_reg; // 100
    
    reg ps2_clk_last;
    reg ps2_clk_reg;
    reg [7:0] ps2_data_reg, ps2_data_next;
    
    reg [2:0] i_reg, i_next;

    reg parity_reg, parity_next;
    reg parity_err_reg, parity_err_next;
    
    wire ps2_posedge;
    assign ps2_posedge = ps2_clk_reg == 1'b1 && ps2_clk_last == 1'b0 ? 1'b1 : 1'b0;
    
    reg[3:0] data_cnt_reg, data_cnt_next;
    
    reg[15:0] out_reg, out_next;
    assign out = out_reg;
    
    always@(posedge clk, negedge rst_n)
        if (!rst_n) begin
            out_reg      <= 16'h0000;
            state_reg    <= start_state;
            data_cnt_reg <= 4'h0;
            ps2_clk_last <= 1'b1;
            ps2_clk_reg  <= 1'b1;
            ps2_data_reg <= 8'h00;
            i_reg        <= 3'b000;
            parity_reg   <= 1'b1;
            parity_err_reg   <= 1'b0;
        end
        else begin
            out_reg      <= out_next;
            state_reg    <= state_next;
            data_cnt_reg <= data_cnt_next;
            ps2_clk_last <= ps2_clk_reg;
            ps2_clk_reg  <= ps2_clk;
            ps2_data_reg <= ps2_data_next;
            i_reg        <= i_next;
            parity_reg <= parity_next;
            parity_err_reg <= parity_err_next;
        end
    
    always @(*) begin
        state_next    = state_reg;
        data_cnt_next = data_cnt_reg;
        ps2_data_next = ps2_data_reg;
        out_next      = out_reg;
        i_next        = i_reg;
        
        case (state_reg)
            start_state: begin
                if ((ps2_dat == 1'b0) && (ps2_posedge == 1'b1)) begin
                    state_next = data_state;
                    parity_err_next = 1'b0;
                    parity_next     = 1'b1;
                end
            end
            data_state: begin
                if (ps2_posedge == 1'b1) begin
                    ps2_data_next = {ps2_dat, ps2_data_reg[7:1]};
                    parity_next = parity_next ^ ps2_dat;
                    if (data_cnt_next == 4'h7) begin
                        data_cnt_next = 4'h0;
                        state_next    = parity_state;
                        end else begin
                            data_cnt_next = data_cnt_reg + 1'b1;
                        end
                    end
                end
                parity_state:
                begin
                    if (ps2_posedge == 1'b1) begin
                        if (parity_next == !ps2_dat) begin
                            parity_err_next = 1'b1;
                        end
                        state_next = end_state;
                    end
                end
                end_state:
                begin
                    if (ps2_posedge == 1'b1) begin
                        if(ps2_dat == 1'b1 && parity_err_next == 1'b0) begin
                        if (i_next == 3'b000) begin
                            out_next = ps2_data_reg;
                            i_next = 3'b001;
                            end else if (i_next == 3'b001) begin
                                if (ps2_data_next == 8'hF0) begin
                                    i_next   = 3'b011;
                                    out_next = {ps2_data_reg , out_reg[7:0]};
                                    end else if (ps2_data_next == out_next[7:0]) begin
                                        out_next = ps2_data_next;
                                        i_next   = 3'b010;
                                        end else begin
                                            out_next = { out_reg[7:0], ps2_data_reg};
                                            i_next   = 3'b100;
                                        end
                                        end else if (i_next == 3'b010) begin
                                            if (ps2_data_next == 8'hF0) begin
                                                i_next   = 3'b011;
                                                out_next = {ps2_data_reg , out_reg[7:0]};
                                                end else begin
                                                    i_next = 3'b010;
                                                end
                                                end else if (i_next == 3'b011) begin // zavrsno
                                                    i_next = 3'b000;
                                                    end else if (i_next == 3'b100) begin
                                                        if (ps2_data_next == 8'hF0) begin
                                                            i_next = 3'b011;
                                                            end else begin
                                                                i_next = 3'b100;
                                                            end
                                                        end
                        end
                                                        state_next    = start_state;
                                                        ps2_data_next = 8'h00;
                                                    end
                                                end
                                                default:
                                                state_next = start_state;
        endcase
    end
endmodule
