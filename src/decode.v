`include "constant.v"

module decode(
    input clk,
    input rst,
    input rdy,

    //fetcher
    input [`DATA_WIDTH] in_fetcher_instr,
    input [`DATA_WIDTH] in_fetcher_pc,
    input in_fetcher_jump_ce,

    //communicate with register for value
    output [`REG_TAG_WIDTH] out_reg_tag1,
    input [`DATA_WIDTH] in_reg_value1,
    input [`ROB_TAG_WIDTH] in_reg_robtag1,
    input in_reg_busy1,

    output [`REG_TAG_WIDTH] out_reg_tag2,
    input [`DATA_WIDTH] in_reg_value2,
    input [`ROB_TAG_WIDTH] in_reg_robtag2,
    input in_reg_busy2,

    //update register renaming
    output reg [`REG_TAG_WIDTH] out_reg_destination,
    output [`ROB_TAG_WIDTH] out_reg_rob_tag,

    //get free rob entry tag
    input [`ROB_TAG_WIDTH] in_rob_freetag,

    //communicate with rob for commited value
    output [`ROB_TAG_WIDTH] out_rob_fetch_tag1,
    input [`DATA_WIDTH] in_rob_fetch_value1,
    input in_rob_fetch_ready1,

    output [`ROB_TAG_WIDTH] out_rob_fetch_tag2,
    input [`DATA_WIDTH] in_rob_fetch_value2,
    input in_rob_fetch_ready2,

    //enable rob to store 
    output reg [`DATA_WIDTH] out_rob_destination,
    output reg [`INSIDE_OPCODE_WIDTH] out_rob_op,
    output out_rob_jump_ce,

    //enable rs to stroe
    output reg [`ROB_TAG_WIDTH] out_rs_rob_tag,
    output reg [`INSIDE_OPCODE_WIDTH] out_rs_op,
    output reg [`DATA_WIDTH] out_rs_value1,
    output reg [`DATA_WIDTH] out_rs_value2,
    output reg [`ROB_TAG_WIDTH] out_rs_tag1,
    output reg [`ROB_TAG_WIDTH] out_rs_tag2,
    output reg [`DATA_WIDTH] out_rs_imm,
    //for rs and rob
    output [`DATA_WIDTH] out_pc,

    //enable slb to store
    output reg [`ROB_TAG_WIDTH] out_slb_rob_tag,
    output reg [`INSIDE_OPCODE_WIDTH] out_slb_op,
    output reg [`DATA_WIDTH] out_slb_value1,
    output reg [`DATA_WIDTH] out_slb_value2,
    output reg [`ROB_TAG_WIDTH] out_slb_tag1,
    output reg [`ROB_TAG_WIDTH] out_slb_tag2,
    output reg [`DATA_WIDTH] out_slb_imm
);
    wire [6:0] opcode;
    wire [4:0] rd;
    wire [2:0] funct3;
    wire [6:0] funct7;
    parameter LUI     = 7'b0110111,//55
              AUIPC   = 7'b0010111,//23
              JAL     = 7'b1101111,//111
              JALR    = 7'b1100111,//103
              B_TYPE  = 7'b1100011,//99
              LI_TYPE = 7'b0000011,//3
              S_TYPE  = 7'b0100011,//35
              AI_TYPE = 7'b0010011,//19
              R_TYPE  = 7'b0110011;//51
              
    assign opcode = in_fetcher_instr[`OPCODE_WIDTH];
    assign funct3 = in_fetcher_instr[14:12];
    assign funct7 = in_fetcher_instr[31:25];
    assign rd = in_fetcher_instr[11:7];

    //logic
    assign out_reg_tag1 = in_fetcher_instr[19:15];
    assign out_reg_tag2 = in_fetcher_instr[24:20];
    assign out_rob_fetch_tag1 = in_reg_robtag1;
    assign out_rob_fetch_tag2 = in_reg_robtag2;
    assign out_reg_rob_tag = in_rob_freetag;
    assign out_pc = in_fetcher_pc;
    assign out_rob_jump_ce = in_fetcher_jump_ce;

    wire [`DATA_WIDTH] value1;
    wire [`DATA_WIDTH] value2;
    wire [`ROB_TAG_WIDTH] tag1;
    wire [`ROB_TAG_WIDTH] tag2;
    assign value1 = (in_reg_busy1 == `FALSE) ? in_reg_value1 : 
                    (in_rob_fetch_ready1 == `TRUE) ? in_rob_fetch_value1 : 
                    `ZERO_DATA;
    assign value2 = (in_reg_busy2 == `FALSE) ? in_reg_value2 : 
                    (in_rob_fetch_ready2 == `TRUE) ? in_rob_fetch_value2 : 
                    `ZERO_DATA;
    assign tag1 = (in_reg_busy1 == `FALSE) ? `ZERO_TAG_ROB :
                  (in_rob_fetch_ready1 == `TRUE) ? `ZERO_TAG_ROB : 
                  in_reg_robtag1;
    assign tag2 = (in_reg_busy2 == `FALSE) ? `ZERO_TAG_ROB :
                  (in_rob_fetch_ready2 == `TRUE) ? `ZERO_TAG_ROB : 
                  in_reg_robtag2;
    always @(*) begin
        out_rob_destination = `ZERO_TAG_REG;
        out_rob_op = `NOP;
        out_rs_rob_tag = `ZERO_TAG_ROB;
        out_rs_op = `NOP;
        out_rs_imm = `ZERO_DATA;
        out_slb_op = `NOP;
        out_slb_imm = `ZERO_DATA;
        out_slb_rob_tag = `ZERO_TAG_ROB;
        out_reg_destination = `ZERO_TAG_REG;
        out_rs_value1 = `ZERO_DATA;
        out_rs_value2 = `ZERO_DATA;
        out_rs_tag1 = `ZERO_TAG_ROB;
        out_rs_tag2 = `ZERO_TAG_ROB;
        out_slb_value1 = `ZERO_DATA;
        out_slb_value2 = `ZERO_DATA;
        out_slb_tag1 = `ZERO_TAG_ROB;
        out_slb_tag2 = `ZERO_TAG_ROB;

        if(rst == `FALSE && rdy == `TRUE) begin 
            // $display("opcode here : %d",opcode);
            case (opcode)
                LUI:begin
                    // $display("LUI");
                  out_rob_op = `LUI;
                  out_rob_destination = {27'b0,rd[4:0]};
                  out_rs_rob_tag = in_rob_freetag;
                  out_rs_op = `LUI;
                  out_rs_imm = {in_fetcher_instr[31:12],12'b0};
                  out_reg_destination = rd;
                end
                AUIPC:begin
                  out_rob_op = `AUIPC;
                  out_rob_destination = {27'b0,rd[4:0]};
                  out_rs_rob_tag = in_rob_freetag;
                  out_rs_op = `AUIPC;
                  out_rs_imm = {in_fetcher_instr[31:12],12'b0};
                  out_reg_destination = rd;
                end
                JAL:begin 
                    out_rob_op = `JAL;
                    out_rob_destination = {27'b0,rd[4:0]};
                    out_rs_rob_tag = in_rob_freetag;
                    out_rs_op = `JAL;
                    out_reg_destination = rd;
                end
                JALR:begin 
                    out_rob_op = `JALR;
                    out_rob_destination = {27'b0,rd[4:0]};
                    out_rs_rob_tag = in_rob_freetag;
                    out_rs_op = `JALR;
                    out_rs_value1 = value1;
                    out_rs_tag1 = tag1;
                    out_rs_imm = {{21{in_fetcher_instr[31]}},in_fetcher_instr[30:20]};
                    out_reg_destination = rd;
                end
                B_TYPE:begin 
                    out_rs_rob_tag = in_rob_freetag;
                    out_rs_value1 = value1;
                    out_rs_tag1 = tag1;
                    out_rs_value2 = value2;
                    out_rs_tag2 = tag2;
                    out_rs_imm = {{20{in_fetcher_instr[31]}},in_fetcher_instr[7],in_fetcher_instr[30:25],in_fetcher_instr[11:8], 1'b0};
                    case(funct3) 
                        3'b000:begin    out_rs_op = `BEQ;     out_rob_op = `BEQ; end
                        3'b001:begin    out_rs_op = `BNE;     out_rob_op = `BNE; end
                        3'b100:begin    out_rs_op = `BLT;     out_rob_op = `BLT; end
                        3'b101:begin    out_rs_op = `BGE;     out_rob_op = `BGE; end
                        3'b110:begin    out_rs_op = `BLTU;    out_rob_op = `BLTU; end
                        3'b111:begin    out_rs_op = `BGEU;    out_rob_op = `BGEU; end
                    endcase
                end
                LI_TYPE:begin 
                    out_rob_destination = {27'b0,rd[4:0]};
                    out_slb_rob_tag = in_rob_freetag;
                    out_slb_value1 = value1;
                    out_slb_tag1 = tag1;
                    out_slb_imm = {{21{in_fetcher_instr[31]}},in_fetcher_instr[30:20]};
                    out_reg_destination = rd;
                    case(funct3) 
                        3'b000:begin    out_slb_op = `LB;     out_rob_op = `LB; end
                        3'b001:begin    out_slb_op = `LH;     out_rob_op = `LH; end
                        3'b010:begin    out_slb_op = `LW;     out_rob_op = `LW; end
                        3'b100:begin    out_slb_op = `LBU;    out_rob_op = `LBU; end
                        3'b101:begin    out_slb_op = `LHU;    out_rob_op = `LHU; end
                    endcase
                end
                S_TYPE:begin
                    out_slb_rob_tag = in_rob_freetag;
                    out_slb_value1 = value1;
                    out_slb_tag1 = tag1;
                    out_slb_value2 = value2;
                    out_slb_tag2 = tag2;
                    out_slb_imm = {{21{in_fetcher_instr[31]}},in_fetcher_instr[30:25],in_fetcher_instr[11:7]};
                    case(funct3) 
                        3'b000:begin    out_slb_op = `SB;    out_rob_op = `SB; end
                        3'b001:begin    out_slb_op = `SH;    out_rob_op = `SH; end
                        3'b010:begin    out_slb_op = `SW;    out_rob_op = `SW; end
                    endcase
                end
                AI_TYPE:begin 
                    out_rob_destination = {27'b0,rd[4:0]};
                    out_rs_rob_tag = in_rob_freetag;
                    out_rs_value1 = value1;
                    out_rs_tag1 = tag1;
                    out_rs_imm = {{21{in_fetcher_instr[31]}},in_fetcher_instr[30:20]};
                    out_reg_destination = rd;
                    case(funct3) 
                        3'b000:begin    out_rs_op = `ADDI;    out_rob_op = `ADDI; end
                        3'b010:begin    out_rs_op = `SLTI;    out_rob_op = `SLTI; end
                        3'b011:begin    out_rs_op = `SLTIU;   out_rob_op = `SLTIU; end
                        3'b100:begin    out_rs_op = `XORI;    out_rob_op = `XORI; end
                        3'b110:begin    out_rs_op = `ORI;     out_rob_op = `ORI; end
                        3'b111:begin    out_rs_op = `ANDI;    out_rob_op = `ANDI; end
                        3'b001:begin 
                            out_rs_op = `SLLI;
                            out_rob_op = `SLLI;
                            out_rs_imm = {26'b0,in_fetcher_instr[25:20]};
                        end
                        3'b101:begin 
                            out_rs_imm = {26'b0,in_fetcher_instr[25:20]};
                            case(funct7)
                                7'b0000000:begin out_rs_op = `SRLI; out_rob_op = `SRLI; end
                                7'b0100000:begin out_rs_op = `SRAI; out_rob_op = `SRAI; end
                            endcase
                        end
                    endcase
                end
                R_TYPE:begin 
                    out_rob_destination = {27'b0,rd[4:0]};
                    out_rs_rob_tag = in_rob_freetag;
                    out_rs_value1 = value1;
                    out_rs_tag1 = tag1;
                    out_rs_value2 = value2;
                    out_rs_tag2 = tag2;
                    out_reg_destination = rd;
                    case(funct3)
                        3'b000:begin 
                            case(funct7)
                                7'b0000000:begin out_rs_op = `ADD; out_rob_op = `ADD; end
                                7'b0100000:begin out_rs_op = `SUB; out_rob_op = `SUB; end
                            endcase
                        end
                        3'b001:begin out_rs_op = `SLL; out_rob_op = `SLL; end
                        3'b010:begin out_rs_op = `SLT; out_rob_op = `SLT; end
                        3'b011:begin out_rs_op = `SLTU; out_rob_op = `SLTU; end
                        3'b100:begin out_rs_op = `XOR; out_rob_op = `XOR; end
                        3'b101:begin 
                            case(funct7)
                                7'b0000000:begin out_rs_op = `SRL; out_rob_op = `SRL; end
                                7'b0100000:begin out_rs_op = `SRA; out_rob_op = `SRA; end
                            endcase
                        end
                        3'b110:begin out_rs_op = `OR; out_rob_op = `OR; end
                        3'b111:begin out_rs_op = `AND; out_rob_op = `AND; end
                    endcase
                end
            endcase
            // $display("out_rob_op : %d",out_rob_op);
        end
    end
    endmodule