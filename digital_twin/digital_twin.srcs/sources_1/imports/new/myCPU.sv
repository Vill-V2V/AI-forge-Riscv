`timescale 1ns / 1ps
module myCPU (
    input  wire        cpu_rst,
    input  wire        cpu_clk,
    output wire [31:0] irom_addr,
    input  wire [31:0] irom_data,
    output wire [31:0] perip_addr,
    output wire        perip_wen,
    output wire [1:0]  perip_mask,
    output wire [31:0] perip_wdata,
    input  wire [31:0] perip_rdata
);

wire stall_if;
wire stall_id;
wire flush_if;
wire flush_ex;
wire id_branch_taken;
wire [31:0] id_jump_target;
wire trap_flush;

wire [31:0] reg_rdata1;
wire [31:0] reg_rdata2;
wire [31:0] wb_wdata;
wire        wb_wen;
wire [4:0]  wb_rd;

wire        mem_wen;
reg  [4:0]  mem_rd;
reg  [31:0] mem_alu_result;
reg  [6:0]  mem_opcode;

// --- IF Stage ---
reg  [31:0] pc;
wire [31:0] next_pc;

always @(posedge cpu_clk or posedge cpu_rst) begin
    if (cpu_rst) begin
        pc <= 32'h8000_0000;
    end else if (!stall_if) begin
        pc <= next_pc;
    end
end

assign irom_addr = pc;

wire [31:0] if_inst;
assign if_inst = (flush_if) ? 32'h00000013 : irom_data;

// --- IF/ID Reg ---
reg [31:0] id_pc;
reg [31:0] id_inst;

always @(posedge cpu_clk or posedge cpu_rst) begin
    if (cpu_rst || flush_if) begin
        id_pc <= 32'b0;
        id_inst <= 32'h00000013;
    end else if (!stall_id) begin
        id_pc <= pc;
        id_inst <= if_inst;
    end
end

// --- ID Stage ---
wire [4:0] rs1;
wire [4:0] rs2;
wire [4:0] rd;
assign rs1 = id_inst[19:15];
assign rs2 = id_inst[24:20];
assign rd  = id_inst[11:7];

wire [6:0] opcode;
wire [6:0] funct7;
wire [2:0] funct3;
assign opcode = id_inst[6:0];
assign funct7 = id_inst[31:25];
assign funct3 = id_inst[14:12];

wire [11:0] id_csr_addr;
assign id_csr_addr = id_inst[31:20];

wire [31:0] id_csr_rdata;
wire        wb_csr_wen;
wire [11:0] wb_csr_addr;
wire [31:0] wb_csr_wdata;
wire [31:0] mtvec_out;
wire [31:0] mepc_out;
wire [31:0] mstatus_out;
wire        trap_enter;
wire        trap_exit;
wire [31:0] trap_pc;
wire [31:0] trap_cause;

CSR_Reg u_CSR (
    .clk(cpu_clk), .rst(cpu_rst),
    .csr_raddr(id_csr_addr), .csr_rdata(id_csr_rdata),
    .csr_waddr(wb_csr_addr), .csr_wen(wb_csr_wen), .csr_wdata(wb_csr_wdata),
    .trap_enter(trap_enter), .trap_exit(trap_exit),
    .trap_pc(trap_pc), .trap_cause(trap_cause),
    .mtvec_out(mtvec_out), .mepc_out(mepc_out), .mstatus_out(mstatus_out)
);

RegFile u_RegFile (
    .clk(cpu_clk), .rs1(rs1), .rs2(rs2),
    .rdata1(reg_rdata1), .rdata2(reg_rdata2),
    .we(wb_wen), .rd(wb_rd), .wdata(wb_wdata)
);

reg [31:0] imm;
always @(*) begin
    if (opcode == 7'b0010011 || opcode == 7'b0000011 || opcode == 7'b1100111 || opcode == 7'b1110011) begin
        imm = {{20{id_inst[31]}}, id_inst[31:20]};
    end else if (opcode == 7'b0100011) begin
        imm = {{20{id_inst[31]}}, id_inst[31:25], id_inst[11:7]};
    end else if (opcode == 7'b1100011) begin
        imm = {{20{id_inst[31]}}, id_inst[7], id_inst[30:25], id_inst[11:8], 1'b0};
    end else if (opcode == 7'b0110111 || opcode == 7'b0010111) begin
        imm = {id_inst[31:12], 12'b0};
    end else if (opcode == 7'b1101111) begin
        imm = {{12{id_inst[31]}}, id_inst[19:12], id_inst[20], id_inst[30:21], 1'b0};
    end else begin
        imm = 32'b0;
    end
end

wire id_fwd_a_mem;
wire id_fwd_b_mem;
wire id_fwd_a_wb;
wire id_fwd_b_wb;

assign id_fwd_a_mem = (mem_wen && mem_rd != 5'b0 && mem_rd == rs1);
assign id_fwd_b_mem = (mem_wen && mem_rd != 5'b0 && mem_rd == rs2);
assign id_fwd_a_wb  = (wb_wen  && wb_rd  != 5'b0 && wb_rd  == rs1);
assign id_fwd_b_wb  = (wb_wen  && wb_rd  != 5'b0 && wb_rd  == rs2);

wire [31:0] cmp_a;
wire [31:0] cmp_b;

assign cmp_a = id_fwd_a_mem ? mem_alu_result : 
               id_fwd_a_wb  ? wb_wdata : reg_rdata1;
assign cmp_b = id_fwd_b_mem ? mem_alu_result : 
               id_fwd_b_wb  ? wb_wdata : reg_rdata2;

wire id_is_branch;
wire id_is_jal;
wire id_is_jalr;

assign id_is_branch = (opcode == 7'b1100011);
assign id_is_jal    = (opcode == 7'b1101111);
assign id_is_jalr   = (opcode == 7'b1100111);

wire id_cmp_eq;
wire id_cmp_lt;
wire id_cmp_ltu;

assign id_cmp_eq  = (cmp_a == cmp_b);
assign id_cmp_lt  = ($signed(cmp_a) < $signed(cmp_b));
assign id_cmp_ltu = (cmp_a < cmp_b);

assign id_branch_taken = (id_is_branch && 
                         ((funct3 == 3'b000 && id_cmp_eq)  || 
                          (funct3 == 3'b001 && !id_cmp_eq) || 
                          (funct3 == 3'b100 && id_cmp_lt)  || 
                          (funct3 == 3'b101 && !id_cmp_lt) || 
                          (funct3 == 3'b110 && id_cmp_ltu) || 
                          (funct3 == 3'b111 && !id_cmp_ltu))) || 
                          id_is_jal || id_is_jalr;

assign id_jump_target = id_is_jalr ? ((cmp_a + imm) & ~32'b1) : (id_pc + imm);

// --- ID/EX Reg ---
reg [31:0] ex_pc;
reg [31:0] ex_rdata1;
reg [31:0] ex_rdata2;
reg [31:0] ex_imm;
reg [31:0] ex_csr_rdata;
reg [4:0]  ex_rd;
reg [4:0]  ex_rs1;
reg [4:0]  ex_rs2;
reg [6:0]  ex_opcode;
reg [6:0]  ex_funct7;
reg [2:0]  ex_funct3;
reg [11:0] ex_csr_addr;

always @(posedge cpu_clk or posedge cpu_rst) begin
    if (cpu_rst || flush_ex) begin
        ex_opcode <= 7'b0;
        ex_rs1 <= 5'b0;
        ex_rs2 <= 5'b0;
        ex_rd <= 5'b0;
        ex_csr_addr <= 12'b0;
    end else begin
        ex_pc <= id_pc;
        ex_rdata1 <= reg_rdata1;
        ex_rdata2 <= reg_rdata2;
        ex_imm <= imm;
        ex_rd <= rd;
        ex_rs1 <= rs1;
        ex_rs2 <= rs2;
        ex_opcode <= opcode;
        ex_funct3 <= funct3;
        ex_funct7 <= funct7;
        ex_csr_addr <= id_csr_addr;
        ex_csr_rdata <= id_csr_rdata;
    end
end

// --- EX Stage ---
wire ex_wen;
assign ex_wen = (ex_rd != 5'b0) && (ex_opcode != 7'b0100011) && (ex_opcode != 7'b1100011) && (ex_opcode != 7'b0);

wire [31:0] forward_a;
wire [31:0] forward_b_reg;

assign forward_a = (mem_wen && (mem_rd == ex_rs1) && (ex_rs1 != 5'b0)) ? mem_alu_result : 
                   (wb_wen  && (wb_rd  == ex_rs1) && (ex_rs1 != 5'b0)) ? wb_wdata : ex_rdata1;
assign forward_b_reg = (mem_wen && (mem_rd == ex_rs2) && (ex_rs2 != 5'b0)) ? mem_alu_result : 
                       (wb_wen  && (wb_rd  == ex_rs2) && (ex_rs2 != 5'b0)) ? wb_wdata : ex_rdata2;

wire use_imm;
assign use_imm = (ex_opcode == 7'b0010011 || ex_opcode == 7'b0000011 || ex_opcode == 7'b0100011);

wire [31:0] alu_a_in;
wire [31:0] alu_b_in;

assign alu_a_in = (ex_opcode == 7'b0010111 || ex_opcode == 7'b1101111) ? ex_pc : forward_a;
assign alu_b_in = (ex_opcode == 7'b0110111 || ex_opcode == 7'b0010111 || ex_opcode == 7'b1101111) ? ex_imm : 
                  use_imm ? ex_imm : forward_b_reg;

wire [31:0] alu_result;
wire alu_zero;
wire alu_lt;
wire alu_ltu;

ALU u_ALU (
    .a(alu_a_in),
    .b(alu_b_in),
    .opcode(ex_opcode),
    .funct3(ex_funct3),
    .funct7(ex_funct7),
    .result(alu_result),
    .zero(alu_zero),
    .lt(alu_lt),
    .ltu(alu_ltu)
);

wire is_csr;
assign is_csr = (ex_opcode == 7'b1110011);

wire [31:0] csr_op_data;
assign csr_op_data = (ex_funct3[2]) ? {27'b0, ex_rs1} : forward_a;

reg  [31:0] ex_csr_wdata;

always @(*) begin
    if (ex_funct3[1:0] == 2'b01) begin
        ex_csr_wdata = csr_op_data;
    end else if (ex_funct3[1:0] == 2'b10) begin
        ex_csr_wdata = ex_csr_rdata | csr_op_data; 
    end else if (ex_funct3[1:0] == 2'b11) begin
        ex_csr_wdata = ex_csr_rdata & ~csr_op_data; 
    end else begin
        ex_csr_wdata = csr_op_data;
    end
end

wire ex_csr_wen;
assign ex_csr_wen = is_csr && (ex_funct3[1:0] != 2'b00);

reg [31:0] mtime;
reg [31:0] mtimecmp;

always @(posedge cpu_clk or posedge cpu_rst) begin
    if (cpu_rst) begin
        mtime <= 32'b0;
        mtimecmp <= 32'hFFFFFFFF;
    end else begin
        mtime <= mtime + 1;
        if (perip_wen && (perip_addr == 32'hE0000000)) begin
            mtime <= perip_wdata;
        end
        if (perip_wen && (perip_addr == 32'hE0000004)) begin
            mtimecmp <= perip_wdata;
        end
    end
end

wire timer_irq;
assign timer_irq = (mtime >= mtimecmp);

wire take_interrupt;
assign take_interrupt = timer_irq && mstatus_out[3];

wire is_ecall;
wire is_mret;

assign is_ecall = is_csr && (ex_funct3 == 3'b000) && (ex_imm[11:0] == 12'h000);
assign is_mret  = is_csr && (ex_funct3 == 3'b000) && (ex_imm[11:0] == 12'h302);

assign trap_enter = is_ecall || take_interrupt;
assign trap_exit  = is_mret;
assign trap_pc    = ex_pc;
assign trap_cause = take_interrupt ? 32'h80000007 : 32'd11;

assign trap_flush = trap_enter || trap_exit;

wire load_use_hazard;
assign load_use_hazard = (ex_opcode == 7'b0000011) && (ex_rd != 5'b0) && ((ex_rd == rs1) || (ex_rd == rs2));

reg mem_opcode_is_load;
always @(*) begin
    mem_opcode_is_load = (mem_opcode == 7'b0000011);
end

wire branch_stall;
assign branch_stall = (id_is_branch || id_is_jalr) && 
                      ( (ex_wen && ex_rd != 5'b0 && (ex_rd == rs1 || ex_rd == rs2)) || 
                        (mem_opcode_is_load && mem_rd != 5'b0 && (mem_rd == rs1 || mem_rd == rs2)) );

assign stall_if = load_use_hazard || branch_stall;
assign stall_id = load_use_hazard || branch_stall;
assign flush_if = (id_branch_taken && !stall_id) || trap_flush;
assign flush_ex = load_use_hazard || branch_stall || trap_flush; 

assign next_pc = trap_enter ? mtvec_out : 
                 trap_exit  ? mepc_out : 
                 (id_branch_taken && !stall_id) ? id_jump_target : (pc + 4);

// --- EX/MEM Reg ---
reg [31:0] mem_rdata2;
reg [31:0] mem_pc;
reg [2:0]  mem_funct3;
reg [31:0] mem_csr_rdata;
reg [31:0] mem_csr_wdata;
reg [11:0] mem_csr_addr;
reg        mem_csr_wen;

always @(posedge cpu_clk) begin
    if (trap_flush) begin
        mem_rd <= 5'b0;
        mem_opcode <= 7'b0;
        mem_csr_wen <= 1'b0;
    end else begin
        mem_alu_result <= alu_result;
        mem_rdata2 <= forward_b_reg;
        mem_rd <= ex_rd;
        mem_opcode <= ex_opcode;
        mem_funct3 <= ex_funct3;
        mem_pc <= ex_pc;
        mem_csr_rdata <= ex_csr_rdata;
        mem_csr_wdata <= ex_csr_wdata;
        mem_csr_addr  <= ex_csr_addr;
        mem_csr_wen   <= ex_csr_wen;
    end
end

assign mem_wen = (mem_rd != 5'b0) && (mem_opcode != 7'b0100011) && (mem_opcode != 7'b1100011);

// --- MEM Stage ---
assign perip_addr  = mem_alu_result;
assign perip_wdata = (mem_funct3 == 3'b000) ? {4{mem_rdata2[7:0]}} : 
                     (mem_funct3 == 3'b001) ? {2{mem_rdata2[15:0]}} : mem_rdata2;
assign perip_wen   = (mem_opcode == 7'b0100011) ? 1'b1 : 1'b0;
assign perip_mask  = (mem_funct3 == 3'b000 || mem_funct3 == 3'b100) ? 2'b00 : 
                     (mem_funct3 == 3'b001 || mem_funct3 == 3'b101) ? 2'b01 : 2'b10;

// --- MEM/WB Reg ---
reg [31:0] wb_alu_result;
reg [31:0] wb_pc;
reg [4:0]  wb_rd_reg; 
reg [6:0]  wb_opcode; 
reg [2:0]  wb_funct3; 
reg [31:0] wb_csr_rdata_reg;
reg [31:0] wb_mem_rdata;

wire is_mtime_read;
wire is_mtimecmp_read;

assign is_mtime_read = (mem_alu_result == 32'hE0000000);
assign is_mtimecmp_read = (mem_alu_result == 32'hE0000004);

wire [31:0] actual_perip_rdata;
assign actual_perip_rdata = is_mtime_read ? mtime : 
                            is_mtimecmp_read ? mtimecmp : perip_rdata;

always @(posedge cpu_clk) begin
    wb_alu_result <= mem_alu_result; 
    wb_rd_reg <= mem_rd;
    wb_opcode <= mem_opcode;
    wb_funct3 <= mem_funct3;
    wb_pc <= mem_pc;
    wb_csr_rdata_reg <= mem_csr_rdata;
    wb_mem_rdata <= actual_perip_rdata;
end

assign wb_csr_wen = mem_csr_wen; 
assign wb_csr_addr = mem_csr_addr; 
assign wb_csr_wdata = mem_csr_wdata;

// --- WB Stage ---
assign wb_rd  = wb_rd_reg;
assign wb_wen = (wb_rd != 5'b0) && (wb_opcode != 7'b0100011) && (wb_opcode != 7'b1100011) && (wb_opcode != 7'b0);

reg [31:0] load_data;
always @(*) begin
    if (wb_funct3 == 3'b000) begin
        load_data = {{24{wb_mem_rdata[7]}}, wb_mem_rdata[7:0]};
    end else if (wb_funct3 == 3'b001) begin
        load_data = {{16{wb_mem_rdata[15]}}, wb_mem_rdata[15:0]};
    end else if (wb_funct3 == 3'b100) begin
        load_data = {24'b0, wb_mem_rdata[7:0]};
    end else if (wb_funct3 == 3'b101) begin
        load_data = {16'b0, wb_mem_rdata[15:0]};
    end else begin
        load_data = wb_mem_rdata;
    end
end

assign wb_wdata = (wb_opcode == 7'b0000011) ? load_data : 
                  (wb_opcode == 7'b1101111 || wb_opcode == 7'b1100111) ? (wb_pc + 4) : 
                  (wb_opcode == 7'b1110011) ? wb_csr_rdata_reg : wb_alu_result;

endmodule