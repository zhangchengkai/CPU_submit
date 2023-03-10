`include "constant.v"
module rob(
    input clk,
    input rst,
    input rdy,

    //to decoder
    output[`ROB_TAG_WIDTH] out_decode_idle_tag,

    //store requires from decoder
    input [`DATA_WIDTH] in_decode_destination,
    input [`INSIDE_OPCODE_WIDTH] in_decode_op,
    input [`DATA_WIDTH] in_decode_pc,
    input in_decode_jump_ce,

    //requires from decoder for regVal
    input [`ROB_TAG_WIDTH] in_decode_fetch_tag1,
    output [`DATA_WIDTH] out_decode_fetch_value1,
    output out_decode_fetch_ready1,
    input [`ROB_TAG_WIDTH] in_decode_fetch_tag2,
    output [`DATA_WIDTH] out_decode_fetch_value2,
    output out_decode_fetch_ready2,

    //to fetcher
    output out_fetcher_isidle,

    //store requires from fetcher
    input in_fetcher_ce,

    //from alu
    input [`DATA_WIDTH] in_alu_cdb_value,
    input [`DATA_WIDTH] in_alu_cdb_newpc,
    input [`ROB_TAG_WIDTH] in_alu_cdb_tag,

    //from slb
    input [`ROB_TAG_WIDTH] in_slb_cdb_tag,
    input [`DATA_WIDTH] in_slb_cdb_value,
    input [`DATA_WIDTH] in_slb_cdb_destination,
    input in_slb_ioin,

    //answer whether exists address collision
    input [`DATA_WIDTH] in_slb_now_addr,
    output out_slb_check,

    //commit to register
    output reg[`REG_TAG_WIDTH] out_reg_index,
    output reg[`ROB_TAG_WIDTH] out_reg_rob_tag,
    output reg[`DATA_WIDTH] out_reg_value,

    //commit to mem
    output reg out_mem_ce,
    output reg [5:0] out_mem_size,
    output reg [`DATA_WIDTH] out_mem_address,
    output reg [`DATA_WIDTH] out_mem_data,
    output reg out_mem_load_ce,
    input in_mem_ce,
    input [`DATA_WIDTH] in_mem_data,

    //out is_misbranched
    output reg out_misbranch,
    output reg [`DATA_WIDTH] out_newpc,

    //out to BranchPredictor
    output reg out_bp_ce,
    output reg [`BP_TAG_WIDTH] out_bp_tag,
    output reg out_bp_jump_ce,

    //out to CDB
    output reg [`ROB_TAG_WIDTH] out_rob_tag,
    output reg [`DATA_WIDTH] out_value
);
    reg [`DATA_WIDTH] value [(`ROB_SIZE-1):0];
    reg [`DATA_WIDTH] destination [(`ROB_SIZE-1):0];
    reg ready [(`ROB_SIZE-1):0];
    reg [`INSIDE_OPCODE_WIDTH] op [(`ROB_SIZE-1):0];
    reg [`DATA_WIDTH] newpc [(`ROB_SIZE-1):0];
    reg isStore [(`ROB_SIZE-1):0];
    reg isIOread [(`ROB_SIZE-1):0];

    //BP
    reg [`DATA_WIDTH] pcs [(`ROB_SIZE-1):0];
    reg predictions [(`ROB_SIZE-1):0];

    //DATA struct
    reg [`ROB_TAG_WIDTH] head;
    reg [`ROB_TAG_WIDTH] tail;
    wire [`ROB_TAG_WIDTH] nextPtr;
    wire [`ROB_TAG_WIDTH] nowPtr;
    //0 for idle, 1 for busy
    reg status;
    localparam IDLE = 0, WAIT_MEM = 1;

    //logic
    assign nextPtr = tail % (`ROB_SIZE - 1) + 1;
    assign nowPtr = head % (`ROB_SIZE - 1) + 1;
    assign out_decode_idle_tag = (nextPtr == head) ? `ZERO_TAG_ROB : nextPtr;
    assign out_fetcher_isidle = (nextPtr != head) && ((nextPtr % (`ROB_SIZE - 1) + 1 != head));
    assign out_decode_fetch_value1 = value[in_decode_fetch_tag1];
    assign out_decode_fetch_value2 = value[in_decode_fetch_tag2];
    assign out_decode_fetch_ready1 = ready[in_decode_fetch_tag1];
    assign out_decode_fetch_ready2 = ready[in_decode_fetch_tag2];
    assign out_slb_check = (isStore[1]  && in_slb_now_addr == destination[1] ) ||
                           (isStore[2]  && in_slb_now_addr == destination[2] ) ||
                           (isStore[3]  && in_slb_now_addr == destination[3] ) ||
                           (isStore[4]  && in_slb_now_addr == destination[4] ) ||
                           (isStore[5]  && in_slb_now_addr == destination[5] ) ||
                           (isStore[6]  && in_slb_now_addr == destination[6] ) ||
                           (isStore[7]  && in_slb_now_addr == destination[7] ) ||
                           (isStore[8]  && in_slb_now_addr == destination[8] ) ||
                           (isStore[9]  && in_slb_now_addr == destination[9] ) ||
                           (isStore[10] && in_slb_now_addr == destination[10]) ||
                           (isStore[11] && in_slb_now_addr == destination[11]) ||
                           (isStore[12] && in_slb_now_addr == destination[12]) ||
                           (isStore[13] && in_slb_now_addr == destination[13]) ||
                           (isStore[14] && in_slb_now_addr == destination[14]) ||
                           (isStore[15] && in_slb_now_addr == destination[15]);
    integer i;
    always @(posedge clk) begin
        if(rst == `TRUE) begin
            head <= 1;
            tail <= 1;
            out_reg_index <= `ZERO_TAG_REG;
            out_mem_ce <= `FALSE;
            out_mem_load_ce <= `FALSE;
            status <= IDLE;
            out_misbranch <= `FALSE;
            out_bp_ce <= `FALSE;
            out_rob_tag <= `ZERO_TAG_ROB;
            for(i = 0; i < `ROB_SIZE; i = i + 1) begin
                ready[i] <= `FALSE;
                isStore[i] <= `FALSE;
                isIOread[i] <= `FALSE;
            end
        end else if(rdy == `TRUE && out_misbranch == `FALSE) begin
            // $display("ROB here %d %d\n",in_fetcher_ce,in_decode_op);
            out_rob_tag <= `ZERO_TAG_ROB;
            out_reg_index <= `ZERO_TAG_REG;
            out_mem_ce <= `FALSE;
            out_mem_load_ce <= `FALSE;
            out_bp_ce <= `FALSE;
            //
            if(in_fetcher_ce == `TRUE && in_decode_op != `NOP) begin
                pcs[nextPtr] <= in_decode_pc;
                predictions[nextPtr] <= in_decode_jump_ce;
                destination[nextPtr] <= in_decode_destination;
                op[nextPtr] <= in_decode_op;
                // $display("ROB in op : %d",in_decode_op);
                case(in_decode_op)
                    `SB,`SH,`SW : begin
                        isStore[nextPtr] <= `TRUE;
                    end
                    default : begin
                        isStore[nextPtr] <= `FALSE;
                    end
                endcase
                ready[nextPtr] <= `FALSE;
                tail <= nextPtr;
            end
            //alu
            if(in_alu_cdb_tag != `ZERO_TAG_ROB) begin
                value[in_alu_cdb_tag] <= in_alu_cdb_value;
                newpc[in_alu_cdb_tag] <= in_alu_cdb_newpc;
                ready[in_alu_cdb_tag] <= `TRUE;
            end
            //slb
            if(in_slb_cdb_tag != `ZERO_TAG_ROB) begin
                ready[in_slb_cdb_tag] <= (in_slb_ioin == `TRUE) ? `FALSE : `TRUE;
                value[in_slb_cdb_tag] <= in_slb_cdb_value;
                isIOread[in_slb_cdb_tag] <= (in_slb_ioin == `FALSE) ? `FALSE : `TRUE;
                if(isStore[in_slb_cdb_tag]) begin
                    destination[in_slb_cdb_tag] <= in_slb_cdb_destination;
                end
            end
            //commit
            if(ready[nowPtr] == `TRUE && head != tail) begin
                if(status == IDLE) begin
                    // $display("commit here op : %d",op[nowPtr]);
                    case(op[nowPtr])
                        `NOP : begin end
                        `JALR : begin

                            out_reg_index <= destination[nowPtr][`REG_TAG_WIDTH];
                            out_reg_rob_tag <= nowPtr;
                            out_reg_value <= value[nowPtr];
                            out_misbranch <= `TRUE;
                            out_newpc <= newpc[nowPtr];
                        end
                        `BEQ,`BNE,`BLT,`BGE,`BLTU,`BGEU: begin 
                            out_bp_ce <= `TRUE;
                            out_bp_jump_ce <= (value[nowPtr] == `JUMP_ENABLE) ? `TRUE : `FALSE;
                            out_bp_tag <= pcs[nowPtr][`BP_HASH_WIDTH];
                            status <= IDLE;
                            isStore[nowPtr]= `FALSE;
                            head <= nowPtr;
                            if(value[nowPtr] == `JUMP_ENABLE && predictions[nowPtr] == `FALSE) begin
                                out_misbranch <= `TRUE;
                                out_newpc <= newpc[nowPtr];
                            end
                            if(value[nowPtr] == `JUMP_DISABLE && predictions[nowPtr] == `TRUE) begin
                                out_misbranch <=`TRUE;
                                out_newpc <= pcs[nowPtr] + 4;
                            end
                        end
                        `SB : begin
                            status <= WAIT_MEM;
                            out_mem_size <= 1;
                            out_mem_address <= destination[nowPtr];
                            out_mem_data <= value[nowPtr];
                            out_mem_ce <= `TRUE;
                        end
                        `SH : begin
                            status <= WAIT_MEM;
                            out_mem_size <= 2;
                            out_mem_address <= destination[nowPtr];
                            out_mem_data <= value[nowPtr];
                            out_mem_ce <= `TRUE;
                        end
                        `SW : begin
                            status <= WAIT_MEM;
                            out_mem_size <= 4;
                            out_mem_address <= destination[nowPtr];
                            out_mem_data <= value[nowPtr];
                            out_mem_ce <= `TRUE;
                        end
                        default : begin
                            status <= IDLE;
                            out_reg_index <= destination[nowPtr][`REG_TAG_WIDTH];
                            out_reg_rob_tag <= nowPtr;
                            out_reg_value <= value[nowPtr];
                            isStore[nowPtr] <= `FALSE;
                            head <= nowPtr;
                        end
                    endcase
                end else if(status == WAIT_MEM) begin
                    if(in_mem_ce == `TRUE) begin
                        status <= IDLE;
                        isStore[nowPtr] <= `FALSE;
                        head <= nowPtr;
                    end
                end
            end else if(isIOread[nowPtr] == `TRUE && head != tail) begin
                if(status == IDLE) begin
                    status <= WAIT_MEM;
                    out_mem_load_ce <= `TRUE;
                end else if(status == WAIT_MEM) begin
                    if(in_mem_ce == `TRUE) begin
                        status <= IDLE;
                        out_reg_index <= destination[nowPtr][`REG_TAG_WIDTH];
                        out_reg_rob_tag <= nowPtr;
                        out_reg_value <= in_mem_data;
                        value[nowPtr] <= in_mem_data;
                        ready[nowPtr] <= `TRUE;
                        isStore[nowPtr] <= `FALSE;
                        isIOread[nowPtr] <= `FALSE;
                        head <= nowPtr;

                        out_rob_tag <= nowPtr;
                        out_value <= in_mem_data;
                    end
                end
            end
        end else if(rdy == `TRUE && out_misbranch == `TRUE) begin
            out_bp_ce <= `FALSE;
            out_rob_tag <=`ZERO_TAG_ROB;
            out_mem_load_ce <= `FALSE;
            out_misbranch <= `FALSE;
            head <= 1;
            tail <= 1;
            out_reg_index <= `ZERO_TAG_REG;
            out_mem_ce <= `FALSE;
            status <= IDLE;
            for(i = 0; i < `ROB_SIZE; i = i + 1) begin
                ready[i] <= `FALSE;
                value[i] <= `ZERO_DATA;
                isStore[i] <= `FALSE;
                isIOread[i] <= `FALSE;
            end
        end
    end
endmodule