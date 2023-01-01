`include "constant.v"

module slb(
    input clk,
    input rst,
    input rdy,

    // to fetcher
    input in_fetcher_ce,

    output out_fetcher_isidle,

    //ins from decode
    input [`ROB_TAG_WIDTH] in_decode_rob_tag,
    input [`INSIDE_OPCODE_WIDTH] in_decode_op,
    input [`DATA_WIDTH] in_decode_value1,
    input [`DATA_WIDTH] in_decode_value2,
    input [`DATA_WIDTH] in_decode_imm,
    input [`ROB_TAG_WIDTH] in_decode_tag1,
    input [`ROB_TAG_WIDTH] in_decode_tag2,

    //require whether exists address collision
    output [`DATA_WIDTH] out_rob_now_addr,
    input in_rob_check,

    //alu_cdb to update
    input [`ROB_TAG_WIDTH] in_alu_cdb_tag,
    input [`DATA_WIDTH] in_alu_cdb_value,

    //rob_cdb to update
    input [`ROB_TAG_WIDTH] in_rob_cdb_tag,
    input [`DATA_WIDTH] in_rob_cdb_value,

    //to memCtrl
    output reg out_mem_ce,
    output reg [5:0] out_mem_size,
    output reg out_mem_signed,
    output reg [`DATA_WIDTH] out_mem_address,

    //from memCtrl
    input in_mem_ce,
    input [`DATA_WIDTH] in_mem_data,

    //to rob/rs
    output reg [`ROB_TAG_WIDTH] out_rob_tag,
    output reg [`DATA_WIDTH] out_destination,
    output reg [`DATA_WIDTH] out_value,
    output reg out_ioin,

    //whether misbranched
    input in_rob_misbranch

);
    localparam IDLE = 1'b0,WAIT_MEM = 1'b1;
    reg status;
    reg busy[(`SLB_SIZE-1):0];
    reg [`SLB_TAG_WIDTH] head;
    reg [`SLB_TAG_WIDTH] tail;
    reg [`ROB_TAG_WIDTH] tags [(`SLB_SIZE-1):0];
    reg [`INSIDE_OPCODE_WIDTH] op [(`SLB_SIZE-1):0];
    reg [`DATA_WIDTH] address [(`SLB_SIZE-1):0];
    reg  address_ready [(`SLB_SIZE-1):0];
    reg [`DATA_WIDTH] imms [(`SLB_SIZE-1):0];
    reg [`DATA_WIDTH] value1 [(`SLB_SIZE-1):0];
    reg [`DATA_WIDTH] value2 [(`SLB_SIZE-1):0];
    reg [`ROB_TAG_WIDTH] value1_tag [(`SLB_SIZE-1):0];
    reg [`ROB_TAG_WIDTH] value2_tag [(`SLB_SIZE-1):0];
    wire ready_to_calculate_addr [(`SLB_SIZE-1):0];
    wire [`SLB_TAG_WIDTH] calculate_tag;
    wire ready_to_issue [(`SLB_SIZE-1):0];
    wire [`SLB_TAG_WIDTH] nextPtr;
    wire [`SLB_TAG_WIDTH] nowPtr;

    assign nextPtr = tail % (`SLB_SIZE-1) + 1; // 1 - 15 
    assign nowPtr = head % (`SLB_SIZE-1) + 1;
    assign out_fetcher_isidle = (nextPtr != head);
    assign out_rob_now_addr = address[nowPtr];

    genvar i;
    generate
        for(i = 1;i < `SLB_SIZE;i=i+1) begin :BlockA
            assign ready_to_issue[i] = (busy[i] == `TRUE) && (value2_tag[i] == `ZERO_TAG_ROB) && (address_ready[i] == `TRUE);
            assign ready_to_calculate_addr[i] = (busy[i] == `TRUE) && (value1_tag[i] == `ZERO_TAG_ROB) && (address_ready[i] == `FALSE);
        end
    endgenerate

    assign calculate_tag = ready_to_calculate_addr[1] ? 1 : 
                           ready_to_calculate_addr[2] ? 2 : 
                           ready_to_calculate_addr[3] ? 3 :
                           ready_to_calculate_addr[4] ? 4 :
                           ready_to_calculate_addr[5] ? 5 :
                           ready_to_calculate_addr[6] ? 6 :
                           ready_to_calculate_addr[7] ? 7 : 
                           ready_to_calculate_addr[8] ? 8 : 
                           ready_to_calculate_addr[9] ? 9 :
                           ready_to_calculate_addr[10] ? 10 :
                           ready_to_calculate_addr[11] ? 11 :
                           ready_to_calculate_addr[12] ? 12 :
                           ready_to_calculate_addr[13] ? 13 :
                           ready_to_calculate_addr[14] ? 14 :
                           ready_to_calculate_addr[15] ? 15 : 
                           `ZERO_TAG_SLB;

    // Temporal logic
    integer j;
    always @(posedge clk) begin 
        if(rst == `TRUE) begin 
            status <= IDLE; 
            head <= 1; tail <= 1;
            out_rob_tag <= `ZERO_TAG_ROB;
            out_mem_ce <= `FALSE;
            out_mem_address <= `ZERO_DATA;
            out_ioin <= `FALSE;
            for(j = 0;j < `SLB_SIZE;j=j+1) begin 
                busy[j] <= `FALSE;
                address_ready[j] <= `FALSE;
                address[j] <= `ZERO_DATA;
            end
        end else if(rdy == `TRUE && in_rob_misbranch == `FALSE) begin
            // Try to issue S/L instruction to ROB:
            out_rob_tag <= `ZERO_TAG_ROB;
            out_mem_ce <= `FALSE;
            out_destination <= `ZERO_DATA;
            out_ioin <= `FALSE;
            // $display("-----------------------------------------------");
            // $display("nowPtr = %d, op[nowPtr] = %d, address_ready[nowPtr] = %d,   %d  %d",nowPtr,op[nowPtr],address_ready[nowPtr],value1_tag[nowPtr],value2_tag[nowPtr]);
            if(ready_to_issue[nowPtr] == `TRUE) begin 
                if(status == IDLE) begin 
                    case(op[nowPtr])
                        `SB,`SH,`SW: begin
                            status <= IDLE;
                            out_destination <= address[nowPtr];
                            out_value <= value2[nowPtr];
                            out_rob_tag <= tags[nowPtr];
                            busy[nowPtr] <= `FALSE;
                            address_ready[nowPtr] <= `FALSE;
                            head <= nowPtr;
                        end
                        `LB,`LBU: begin
                            if(address[nowPtr] == `IO_ADDRESS) begin //IO input processes when commited
                                status <= IDLE;
                                out_rob_tag <= tags[nowPtr];
                                busy[nowPtr] <= `FALSE;
                                address_ready[nowPtr] <= `FALSE;
                                head <= nowPtr;
                                out_ioin <= `TRUE;
                            end else if(in_rob_check == `FALSE && address[nowPtr] != out_destination) begin
                                status <= WAIT_MEM;
                                out_mem_signed <= (op[nowPtr] == `LB) ? 1 : 0; 
                                out_mem_ce <= `TRUE;
                                out_mem_size <= 1;
                                out_mem_address <= address[nowPtr];
                            end
                        end
                        `LH,`LHU: begin 
                            if(in_rob_check == `FALSE && address[nowPtr] != out_destination) begin
                                status <= WAIT_MEM;
                                out_mem_signed <= (op[nowPtr] == `LH) ? 1 : 0;
                                out_mem_ce <= `TRUE;
                                out_mem_size <= 2;
                                out_mem_address <= address[nowPtr];
                            end
                        end
                        `LW: begin
                            if(in_rob_check == `FALSE && address[nowPtr] != out_destination) begin
                                status <= WAIT_MEM;
                                out_mem_ce <= `TRUE;
                                out_mem_size <= 4;
                                out_mem_address <= address[nowPtr];
                            end
                        end
                    endcase
                end else if(status == WAIT_MEM) begin
                    if(in_mem_ce == `TRUE) begin 
                        // CDB to rs/rob
                        out_rob_tag <= tags[nowPtr];
                        out_value <= in_mem_data;
                        status <= IDLE;
                        busy[nowPtr] <= `FALSE;
                        address_ready[nowPtr] <= `FALSE;
                        head <= nowPtr;
                    end
                end
            end 
            // Calculate effective address per cycle
            if(calculate_tag != `ZERO_TAG_SLB) begin 
                address[calculate_tag] <= value1[calculate_tag] + imms[calculate_tag];
                address_ready[calculate_tag] <= `TRUE;
            end
            // Store new entry into SLB
            if(in_fetcher_ce == `TRUE && in_decode_rob_tag != `ZERO_TAG_ROB && in_decode_op != `NOP) begin
                // $display("SLB in op : %d",in_decode_op);
                busy[nextPtr] <= `TRUE;
                tail <= nextPtr;
                tags[nextPtr] <= in_decode_rob_tag;
                op[nextPtr] <= in_decode_op;
                address_ready[nextPtr] <= `FALSE;
                imms[nextPtr] <= in_decode_imm;
                value1[nextPtr] <= in_decode_value1;
                value2[nextPtr] <= in_decode_value2;
                value1_tag[nextPtr] <= in_decode_tag1;
                value2_tag[nextPtr] <= in_decode_tag2;
                // 时序逻辑，store cdb val
                if(in_alu_cdb_tag != `ZERO_TAG_ROB) begin 
                    if(in_decode_tag1 == in_alu_cdb_tag) begin 
                        value1[nextPtr] <= in_alu_cdb_value;
                        value1_tag[nextPtr] <= `ZERO_TAG_ROB;
                    end
                    if(in_decode_tag2 == in_alu_cdb_tag) begin 
                        value2[nextPtr] <= in_alu_cdb_value;
                        value2_tag[nextPtr] <= `ZERO_TAG_ROB;
                    end
                end
                if(out_rob_tag != `ZERO_TAG_ROB && out_ioin == `FALSE) begin 
                    if(in_decode_tag1 == out_rob_tag) begin 
                        value1[nextPtr] <= out_value;
                        value1_tag[nextPtr] <= `ZERO_TAG_ROB;
                    end
                    if(in_decode_tag2 == out_rob_tag) begin 
                        value2[nextPtr] <= out_value;
                        value2_tag[nextPtr] <= `ZERO_TAG_ROB;
                    end
                end
            end
            
            for(j = 1;j < `SLB_SIZE;j=j+1) begin 
                if(busy[j] == `TRUE) begin 
                    // Monitor ALU CDB
                    if(in_alu_cdb_tag != `ZERO_TAG_ROB) begin
                        if(value1_tag[j] == in_alu_cdb_tag) begin 
                            value1[j] <= in_alu_cdb_value;
                            value1_tag[j] <= `ZERO_TAG_ROB;
                        end 
                        if(value2_tag[j] == in_alu_cdb_tag) begin 
                            value2[j] <= in_alu_cdb_value;
                            value2_tag[j] <= `ZERO_TAG_ROB;
                        end
                    end
                    // Monitor ROB CDB maybe have bugs
                    if(in_rob_cdb_tag != `ZERO_TAG_ROB) begin 
                        if(value1_tag[j] == in_rob_cdb_tag) begin 
                            value1[j] <= in_rob_cdb_value;
                            value1_tag[j] <= `ZERO_TAG_ROB;
                        end 
                        if(value2_tag[j] == in_rob_cdb_tag) begin 
                            value2[j] <= in_rob_cdb_value;
                            value2_tag[j] <= `ZERO_TAG_ROB;
                        end
                    end
                    // Broadcast to itself
                    if(out_rob_tag != `ZERO_TAG_ROB && out_ioin == `FALSE) begin 
                        if(value1_tag[j] == out_rob_tag) begin 
                            value1[j] <= out_value;
                            value1_tag[j] <= `ZERO_TAG_ROB;
                        end 
                        if(value2_tag[j] == out_rob_tag) begin 
                            value2[j] <= out_value;
                            value2_tag[j] <= `ZERO_TAG_ROB;
                        end
                    end
                end
            end

        end else if(rdy == `TRUE && in_rob_misbranch == `TRUE) begin 
            out_rob_tag <= `ZERO_TAG_ROB;
            out_ioin <= `FALSE;
            out_mem_ce <= `FALSE;
            status <= IDLE;
            head <= 1;tail <=1;
            for(j = 1;j < `SLB_SIZE;j=j+1) begin 
                busy[j] <= `FALSE;
                address_ready[j] <= `FALSE;
                address[j] <= `ZERO_DATA;
            end
        end
    end
endmodule