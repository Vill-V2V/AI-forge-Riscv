# RV32I 五级流水线 CPU | FPGA Digital Twin

基于 Verilog/SystemVerilog 实现的 RV32I 处理器与 FPGA 数字孪生 SoC 工程。CPU 采用经典五级流水线架构，包含数据前推、Load-Use 冒险处理、CSR 特权寄存器、异常/中断、UART、定时器及数字孪生外设桥接等模块。

## 项目简介

本项目面向 FPGA 竞赛与处理器设计实践，围绕 RV32I 指令集完成从 CPU 核心到 SoC 外设的软硬件协同验证。

设计重点包括：

- RV32I 基础整数指令集
- 经典五级流水线：IF / ID / EX / MEM / WB
- 数据前推（Data Forwarding）与 Load-Use 冒险处理
- 分支/跳转提前判决与流水线冲刷
- Zicsr 特权指令与 Trap/Interrupt 支持
- 64 位硬件定时器
- UART、GPIO、数码管与数字孪生外设接口
- MounRiver Studio 裸机软件工程

## 项目结构

```text
.
├─ rv32i_cpu/                  # 基础 RV32I CPU 工程
│  ├─ ALU .v
│  ├─ CSR_Reg.v
│  ├─ Register File.v
│  ├─ myCPU.v
│  ├─ tb_myCPU.v
│  ├─ uart_tx.v
│  ├─ os.coe
│  ├─ coe/                     # 测试程序机器码
│  ├─ project_1/               # Vivado 工程文件
│  └─ software/my_first_os/    # MounRiver Studio 裸机工程
├─ digital_twin/               # 数字孪生 SoC 工程
│  ├─ digital_twin.xpr
│  └─ digital_twin.srcs/       # RTL、仿真、约束、IP 配置
├─ docs/
│  └─ 设计文档大纲.docx
├─ README.md
└─ .gitignore
```

## 主要模块

| 模块 | 说明 |
| --- | --- |
| `myCPU` | CPU 顶层，连接取指、译码、执行、访存与写回 |
| `ALU` | 算术逻辑单元，支持 RV32I 运算 |
| `Register File` | 32 × 32 bit 通用寄存器堆 |
| `CSR_Reg` | 机器模式 CSR 与异常/中断支持 |
| `uart_tx` / `uart` | 串口发送与通信 |
| `dram_driver` | 数据存储器访问 |
| `perip_bridge` | 外设地址译码与桥接 |
| `twin_controller` | 数字孪生控制器 |
| `student_top` / `top` | SoC 顶层与板级顶层 |

## 开发环境

- FPGA 开发：Vivado Design Suite 2023.2
- 硬件描述语言：Verilog / SystemVerilog
- 软件开发：MounRiver Studio
- 目标平台：Xilinx FPGA（具体器件型号以工程约束和 `.xpr` 配置为准）

## 快速开始

### 1. 打开 FPGA 工程

基础 CPU 工程：

```text
rv32i_cpu/project_1/project_1.xpr
```

完整数字孪生 SoC 工程：

```text
digital_twin/digital_twin.xpr
```

使用 Vivado 打开对应 `.xpr` 文件，等待 IP 核更新完成后进行综合、实现和下载。

### 2. 编译软件

使用 MounRiver Studio 导入：

```text
rv32i_cpu/software/my_first_os
```

编译后生成的程序可用于软硬协同验证。

### 3. 仿真

Vivado 工程中已包含 `tb_myCPU`、`tb_top`、`tb_uart` 等测试平台，可直接运行行为级仿真。

## 设计要点

### 五级流水线

CPU 将指令执行划分为取指、译码、执行、访存、写回五个阶段，通过流水线寄存器解耦组合逻辑，提高系统主频与指令吞吐率。

### 数据冒险处理

- 全通路数据前推：将 MEM/WB 阶段结果旁路到 EX 阶段
- Load-Use 冒险：检测到相关冲突时阻塞 PC 与流水线寄存器，并插入 NOP

### 控制冒险处理

分支与跳转在 ID 阶段提前判决，配合流水线冲刷逻辑减少跳转开销。

### 特权与异常

实现 CSR 寄存器组、Trap 入口、异常原因记录和定时器中断，为运行裸机程序及后续 RTOS 移植提供基础。

## 说明

- 仓库仅保留源码、工程配置、约束、IP 配置和文档，不包含 Vivado 编译缓存及安装包。
- 若打开工程后提示 IP 需要更新，按 Vivado 提示执行 `Report IP Status` 和 `Upgrade IP` 即可。
- 不同 Vivado 版本可能存在工程兼容性差异，建议使用 Vivado 2023.2。

## License

如需开源，可自行添加 MIT License。
