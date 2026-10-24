module CSR_Reg (
    input  wire        clk,
    input  wire        rst,
    
    input  wire [11:0] csr_raddr,
    output reg  [31:0] csr_rdata,
    input  wire [11:0] csr_waddr,
    input  wire        csr_wen,
    input  wire [31:0] csr_wdata,
    
    input  wire        trap_enter,
    input  wire        trap_exit,
    input  wire [31:0] trap_pc,
    input  wire [31:0] trap_cause,
    
    output wire [31:0] mtvec_out,
    output wire [31:0] mepc_out,
    output wire [31:0] mstatus_out  // 新增：输出系统状态给定时器
);

    reg [31:0] mstatus; 
    reg [31:0] mtvec;   
    reg [31:0] mepc;    
    reg [31:0] mcause;  

    assign mtvec_out = mtvec;
    assign mepc_out  = mepc;
    assign mstatus_out = mstatus;

    always @(*) begin
        case (csr_raddr)
            12'h300: csr_rdata = mstatus;
            12'h305: csr_rdata = mtvec;
            12'h341: csr_rdata = mepc;
            12'h342: csr_rdata = mcause;
            default: csr_rdata = 32'b0;
        endcase
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mstatus <= 32'h00001800; // 默认关闭中断 (MIE=0)
            mtvec   <= 32'b0;
            mepc    <= 32'b0;
            mcause  <= 32'b0;
        end 
        else if (trap_enter) begin
            mepc <= trap_pc;
            mcause <= trap_cause;
            mstatus[7] <= mstatus[3]; 
            mstatus[3] <= 1'b0;       // 进中断后关闭全局中断
        end
        else if (trap_exit) begin
            mstatus[3] <= mstatus[7]; 
            mstatus[7] <= 1'b1;       // 退出中断恢复
        end
        else if (csr_wen) begin
            case (csr_waddr)
                12'h300: mstatus <= csr_wdata;
                12'h305: mtvec   <= csr_wdata;
                12'h341: mepc    <= csr_wdata;
                12'h342: mcause  <= csr_wdata;
            endcase
        end
    end
endmodule