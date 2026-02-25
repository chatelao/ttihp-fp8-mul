# Concept: Streaming MXFP8 MAC Unit for Tiny Tapeout

## 1. Introduction
The scaling of Deep Learning models necessitates efficient numerical representations to overcome the "Memory Wall". The **OCP Microscaling Formats (MX) Specification v1.0** introduces a block-based scaling approach that significantly reduces memory bandwidth and hardware complexity. This concept outlines the implementation of an MXFP8-compatible Multiply-Accumulate (MAC) unit within the strict constraints of a single **1x1 Tiny Tapeout tile** (Sky130).

## 2. Numerical Representation: OCP MXFP8
The implementation focuses on the **MXFP8** format (supporting both E4M3 and E5M2 variants) with a shared block scaling factor.

- **Shared Scale**: UE8M0 (8-bit unsigned integer exponent, power-of-two scaling).
- **Element Formats**:
  - **E4M3**: 1-bit sign, 4-bit exponent, 3-bit mantissa.
  - **E5M2**: 1-bit sign, 5-bit exponent, 2-bit mantissa.
- **Block Size ($k$)**: 32 elements.
- **Mathematical Formula**:
  $$V_i = (-1)^{S_i} \times 2^{E_i - \text{Bias}} \times (1 + M_i) \times 2^X$$
  Where $X$ is the shared UE8M0 scale.

## 3. Architecture: Operand Streaming
To fit within the ~320 D-Flip-Flop (DFF) budget of a 1x1 tile, the design avoids large on-chip buffers and instead employs **Temporal Multiplexing (Operand Streaming)**.

### 3.1. I/O Protocol (38-Cycle Sequence)
The unit communicates with a host (e.g., RP2040) using a strictly timed protocol:

| Phase | Cycles | Input (`ui_in`) | Input (`uio_in`) | Output (`uo_out`) |
|-------|--------|-----------------|------------------|-------------------|
| **IDLE** | 0 | - | - | 0 |
| **LOAD_SCALE** | 1-2 | Scale $X_A$ (C1) | Scale $X_B$ (C2) | 0 |
| **STREAM** | 3-34 | Element $A_i$ | Element $B_i$ | 0 |
| **OUTPUT** | 35-38 | - | - | Accumulator[byte] |

### 3.2. Hardware/Software Co-Design
The hardware computes the dot product of the scaled elements but factors out the shared scales to minimize gate count:
$$C = \left( \sum_{i=1}^{32} \text{FP8}(A_i) \times \text{FP8}(B_i) \right) \times 2^{X_A + X_B}$$
The ASIC performs the summation and the intermediate exponent arithmetic. The final scaling by $2^{X_A + X_B}$ is performed by the host software.

## 4. Microarchitecture
### 4.1. Datapath
1.  **Sign Logic**: $S_{res} = S_A \oplus S_B$.
2.  **Exponent Path**: Adds $E_A$ and $E_B$, subtracts bias.
3.  **Mantissa Multiplier**: 4x4-bit (for E4M3) or 3x3-bit (for E5M2) integer multiplier.
4.  **Alignment Shifter**: A small barrel shifter aligns the product to a fixed-point format based on the local exponent.
5.  **Accumulator**: A 32-bit register stores the running sum.

### 4.2. Control Logic
A Finite State Machine (FSM) manages the cycle transitions and control signals for the registers and the output multiplexer.

## 5. Resource Estimation (1x1 Tile)
Estimated based on the "Streaming MXFP4" baseline, adjusted for 8-bit elements:

- **D-Flip-Flops (DFFs)**:
  - Scale Registers: 16 bits
  - Accumulator: 32 bits
  - FSM & Counters: 12 bits
  - Input/Pipeline Registers: ~24 bits
  - **Total**: ~84-100 DFFs (approx. 30% of 1x1 tile limit).
- **Combinational Logic**:
  - 4x4 Multiplier + Shifter + 32-bit Adder.
  - Estimated **400-700 gates**, well within the routing limits for Sky130.

## 6. Implementation Strategy
The project will use the **OpenLane** flow and **Cocotb** for verification. Test vectors will be generated using the `AMD Quark` library or a custom Python model to ensure OCP MX compliance.
