# SERV Datasheet
Fetched from https://serv.readthedocs.io/en/latest/datasheet.html

## Overview
The SERV RISC-V CPU is an award-winning and highly compact processor core based on the RISC-V instruction set architecture (ISA). It is designed to be the smallest possible RISC-V compliant CPU and is particularly well-suited for embedded systems and applications where silicon area is critical.

## Key Features
- ISA: RISC-V RV32IZifencei
- Optional ISA extensions: C, M, Zicsr
- Optional features: Timer interrupts, Extension interface
- Architecture: Bit-serial (one bit processed per clock cycle)
- Area: Smallest RISC-V core available (approx 2.1kGE in CMOS)

## Extension Interface
The extension interface allows additional functionality to be added to the SERV CPU core through custom accelerators that are called for when specific instructions are encountered.

When SERV detects instructions to be executed by an external accelerator, it treats them as two-stage operations.
- Stage 1: o_ext_rs1 and o_ext_rs2 are prepared (32-bit parallel).
- Valid Signal: SERV asserts a valid signal (e.g. o_mdu_valid).
- Processing: Accelerator performs work.
- Completion: Accelerator returns value in i_ext_rd (32-bit parallel) and strobes i_ext_ready.
- Stage 2: SERV stores the received result.

## Parameters
- MDU: 0 or 1. Enables M-extension interface.
- PRE_REGISTER: 0 or 1.
- RESET_PC
- RESET_STRATEGY
- RF_WIDTH: 2, 4, 8, 16, 32.
- WITH_CSR: 0 or 1.

## Signals
- o_ext_rs1 [31:0]
- o_ext_rs2 [31:0]
- o_ext_funct3 [2:0]
- i_ext_rd [31:0]
- i_ext_ready
- o_mdu_valid
