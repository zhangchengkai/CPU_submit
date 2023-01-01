//BranchPridictor
`include "constant.v"
module bp(
    input clk,
    input rst,
    input rdy,
    //requires from fetcher
    input [`BP_TAG_WIDTH] in_fetcher_tag,

    //answer to fetcher, jump or not
    output wire out_fetcher_jump_ce,

    //feedback from rob commit
    input in_rob_bp_ce,
    input [`BP_TAG_WIDTH] in_rob_tag,
    input in_rob_jump_ce
);
    //Two bit saturation counter
    reg [1:0] predictor_table [(`BP_TABLE_SIZE-1):0];
    assign out_fetcher_jump_ce = predictor_table[in_fetcher_tag][1];

    integer i;
    always@(posedge clk) begin
        if(rst == `TRUE) begin
            for(i=0;i<`BP_TABLE_SIZE;i=i+1) begin
                predictor_table[i] <=2'b01;
            end
        end else if(rdy == `TRUE) begin
            if(in_rob_bp_ce == `TRUE) begin
                if(in_rob_jump_ce == `TRUE) begin
                    predictor_table[in_rob_tag] <= predictor_table[in_rob_tag] + ((predictor_table[in_rob_tag] == 2'b11) ? 0 : 1);
                end else begin
                    predictor_table[in_rob_tag] <= predictor_table[in_rob_tag] + ((predictor_table[in_rob_tag] == 2'b00) ? 0 : -1);
                end
            end
        end
    end
endmodule