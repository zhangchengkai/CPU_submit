`include "constant.v"

module register(
    input clk,
    input rst,
    input rdy,

    //fetcher to update renaming
    input in_fetcher_ce,

    //require from decode
    input [`REG_TAG_WIDTH] in_decode_reg_tag1,
    output [`DATA_WIDTH] out_decode_value1,
    output [`ROB_TAG_WIDTH] out_decode_rob_tag1,
    output out_decode_busy1,
    input [`REG_TAG_WIDTH] in_decode_reg_tag2,
    output [`DATA_WIDTH] out_decode_value2,
    output [`ROB_TAG_WIDTH] out_decode_rob_tag2,
    output out_decode_busy2,

    //updates from decode
    input [`REG_TAG_WIDTH] in_decode_destination_reg,
    input [`ROB_TAG_WIDTH] in_decode_destination_rob,

    //update from rob
    input [`REG_TAG_WIDTH] in_rob_commit_reg,
    input [`ROB_TAG_WIDTH] in_rob_commit_rob,
    input [`DATA_WIDTH] in_rob_commit_value,

    //whether misbranched
    input in_rob_misbranch
);
    reg [`DATA_WIDTH] values [(`REG_SIZE-1):0];
    reg [`ROB_TAG_WIDTH] tags [(`REG_SIZE-1):0];
    reg busy [(`REG_SIZE-1):0];

    assign out_decode_value1 = values[in_decode_reg_tag1];
    assign out_decode_rob_tag1 = tags[in_decode_reg_tag1];
    assign out_decode_busy1 = busy[in_decode_reg_tag1];
    assign out_decode_value2 = values[in_decode_reg_tag2];
    assign out_decode_rob_tag2 = tags[in_decode_reg_tag2];
    assign out_decode_busy2 = busy[in_decode_reg_tag2];

        integer i;
    always @(posedge clk) begin
        if(rst == `TRUE) begin
            values[0] <= `ZERO_DATA;
            busy[0] <= `FALSE;
            tags[0] <= `ZERO_TAG_ROB;
        end
        // for(i=0;i<`REG_SIZE;i=i+1) begin
        //     $write("%d",tags[i]);
        // end
        // $display("");
    end

    genvar k;
    generate
        for(k=1;k<`REG_SIZE;k=k+1) begin : werwer
            always @(posedge clk) begin
                if(rst == `TRUE) begin
                    values[k] <= `ZERO_DATA; 
                    busy[k] <= `FALSE;
                    tags[k] <= `ZERO_TAG_ROB;
                end else if(rst == `FALSE && rdy == `TRUE) begin
                    if(in_rob_commit_reg == k) begin
                        values[k] <= in_rob_commit_value;
                        if(in_rob_commit_rob == tags[k]) begin
                            busy[k] <= `FALSE;
                        end
                    end
                    if(in_fetcher_ce == `TRUE && in_decode_destination_reg == k) begin
                        busy[k] <= `TRUE;
                        tags[k] <= in_decode_destination_rob;
                    end
                    if(in_rob_misbranch == `TRUE) begin
                        busy[k] <= `FALSE;
                        tags[k] <= `ZERO_TAG_ROB;
                    end
                end
            end
        end
    endgenerate
endmodule