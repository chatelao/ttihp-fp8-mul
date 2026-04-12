# Snitch Core Architectural Overview

This document describes the architecture of the Snitch core as implemented in the `snitch-core` directory. Snitch is a high-efficiency integer core (RV32E) designed to orchestrate compute-heavy tasks by offloading complex operations to accelerators (like the FPU or MAC unit).

## 1. Instruction Lifecycle: "The Before"

The Snitch pipeline begins with instruction fetch and decoding, handled primarily in `snitch.sv`.

### PC Management & Fetch
- **Program Counter (PC)**: Managed via `pc_q` and `pc_d`. The next PC is determined combinatorially based on the current state (sequential, branch/jump, exception, or return from trap).
- **Instruction Interface**: Uses a simple valid/ready handshake (`inst_valid_o`, `inst_ready_i`).
- **ITLB**: An L0 Instruction TLB (`snitch_l0_tlb.sv`) provides single-cycle virtual-to-physical address translation for the fetch stage when virtual memory (VM) is enabled.

### Decoding and Dispatch
The decoder analyzes the instruction word (`inst_data_i`) and determines the execution path:
- **Internal Execution**: Basic RISC-V integer operations (ADD, SUB, XOR, etc.), branches, and jumps are handled by the internal ALU.
- **Accelerator Offloading**: Instructions requiring specialized hardware (MUL/DIV, Bit-manipulation, FPU, Vector, DMA) are dispatched to the **Accelerator Interface**.
- **Memory Operations**: Load and Store instructions are dispatched to the **Load-Store Unit (LSU)**.

## 2. Computation: "The During" (Offloading Mechanism)

Snitch follows a decoupled execution model. Instead of having complex functional units in the main pipeline, it issues requests to external units.

### The Accelerator Interface
- **Request (`acc_qreq_o`)**: When an offloadable instruction is issued, the core sends a request containing:
    - `id`: The destination register (RD).
    - `data_op`: The raw instruction word (for the accelerator's internal decoder).
    - `data_arga`, `data_argb`: Operand values read from the General Purpose Registers (GPR).
    - `data_argc`: Additional context, often the physical address for memory-related accelerator tasks.
- **Handshaking**: Uses `acc_qvalid_o` and `acc_qready_i`. If the accelerator is busy, the core stalls.

### Load-Store Unit (LSU)
- **Decoupled Memory Access**: The LSU (`snitch_lsu.sv`) manages outstanding memory transactions.
- **Load Address Queue (LAQ)**: Tracks pending loads to ensure results are returned to the correct register in the correct order.
- **DTLB**: Similar to the ITLB, a Data TLB provides address translation for memory accesses.

## 3. Completion: "The After" (Scoreboard & Retirement)

Because accelerators and memory loads can take multiple cycles (and may complete out-of-order relative to the main pipeline), Snitch uses a **Scoreboard** to maintain data integrity.

### Scoreboard (`sb_q`)
- **Dependency Tracking**: When a load or accelerator instruction is issued, a bit is set in the scoreboard for the destination register (`rd`).
- **Hazard Prevention**: The pipeline stalls if a new instruction tries to use a register that is marked "busy" in the scoreboard.
- **Operand Readiness**: `opa_ready` and `opb_ready` checks ensure that source operands are available before an instruction is issued.

### Retirement and Write-back
- **Internal Retirement**: ALU instructions retire in a single cycle if no stalls are present.
- **Asynchronous Retirement**:
    - **LSU Results**: When data returns from memory, the LSU asserts `lsu_pvalid`. The core captures the data, writes it to the GPR, and clears the scoreboard bit for the target register.
    - **Accelerator Results**: When an accelerator completes, it sends a response (`acc_prsp_i`) containing the result and the original `id`. The core performs the write-back and clears the scoreboard bit.
- **Conflict Resolution**: The write-back logic prioritizes internal retirement, then LSU results, then accelerator results to handle simultaneous completions.

## 4. Integration with a MAC Unit

A MAC unit (like the OCP MXFP8 unit in this repository) would typically interface with Snitch as an accelerator.
1. **Issue**: Snitch decodes a custom MAC instruction, reads two operands (or vectors) from its GPR, and sends them to the MAC via `acc_qreq_o`.
2. **Execute**: The MAC unit processes the data (e.g., performing a dot product over multiple cycles).
3. **Retire**: Once the final sum is ready, the MAC unit sends the result back via `acc_prsp_i`. Snitch then writes this result into the target register, allowing subsequent instructions to use it.

This decoupled architecture allows Snitch to remain small and simple while leveraging powerful specialized hardware for computation.
