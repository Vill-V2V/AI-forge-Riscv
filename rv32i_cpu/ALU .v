module ALU (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [6:0]  opcode,
    input  wire [2:0]  funct3,
    input  wire [6:0]  funct7,
    output reg  [31:0] result,
    output wire        zero,
    output wire        lt,
    output wire        ltu
);

    wire is_r_type = (opcode == 7'b0110011);
    wire is_i_type = (opcode == 7'b0010011);
    
    // 提取移位位数 (Shamt)
    wire [4:0] shamt = b[4:0];

    always @(*) begin
        if (opcode == 7'b0110111 || opcode == 7'b0010111) begin
            // LUI (Result = Imm), AUIPC (Result = PC + Imm)
            if (opcode == 7'b0010111) result = a + b; // AUIPC
            else result = b; // LUI
        end 
        else if (opcode == 7'b1101111 || opcode == 7'b1100111) begin
            // JAL, JALR
            result = a + b; 
        end
        else if (opcode == 7'b0000011 || opcode == 7'b0100011) begin
            // Load, Store (Address calculation)
            result = a + b;
        end
        else if (is_r_type || is_i_type) begin
            case (funct3)
                3'b000: result = (is_r_type && funct7[5]) ? (a - b) : (a + b); // ADD / SUB (I-Type 只有 ADDI)
                3'b001: result = a << shamt;                                   // SLL / SLLI
                3'b010: result = ($signed(a) < $signed(b)) ? 32'b1 : 32'b0;    // SLT / SLTI
                3'b011: result = (a < b) ? 32'b1 : 32'b0;                      // SLTU / SLTIU
                3'b100: result = a ^ b;                                        // XOR / XORI
                3'b101: result = funct7[5] ? ($signed(a) >>> shamt) : (a >> shamt); // SRA / SRAI / SRL / SRLI
                3'b110: result = a | b;                                        // OR / ORI
                3'b111: result = a & b;                                        // AND / ANDI
                default: result = 32'b0;
            endcase
        end 
        else begin
            // Branch comparison usually done directly, but ALU provides flags
            result = a - b; 
        end
    end

    // 比较标志位提取，供 Branch 单元使用
    assign zero = (a == b);
    assign lt   = ($signed(a) < $signed(b));
    assign ltu  = (a < b);

endmodule