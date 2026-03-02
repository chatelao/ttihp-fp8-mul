# Concept: Bit-Serial OCP MX MAC Unit (OCP-MX-SERIAL)

## 1. Introduction
While the current streaming implementation of the OCP MX MAC unit is optimized for throughput and fits within a 1x2 Tiny Tapeout tile, certain ultra-constrained applications (e.g., thousands of units in a large-scale systolic array or 1x1 tile targets with high feature sets) require even smaller footprints.

Inspired by **SERV** (the award-winning bit-serial RISC-V core), this concept proposes a **purely bit-serial implementation** of the OCP MX specification. By processing data one bit at a time, we can trade off latency for a significant reduction in gate count and routing congestion.

## 2. Core Philosophy: The SERV Approach
The fundamental principle of SERV is that any N-bit operation can be decomposed into N 1-bit operations over N clock cycles. For an OCP MX MAC unit, this means:
- **Registers as Shift Registers**: Operands, exponents, and the accumulator are stored in shift registers or small bit-serial memories.
- **1-Bit Datapath**: All arithmetic (addition, multiplication, shifting) is performed using 1-bit full adders and minimal control logic.
- **Latency-Area Tradeoff**: An 8-bit multiplication that takes 1 cycle in a parallel multiplier will take ~64 cycles in a bit-serial multiplier, but use ~1/10th of the area.

## 3. Bit-Serial Architecture

### 3.1. Serial Decoder
Instead of a parallel decoder that unpacks S, E, and M fields in one cycle, the serial decoder processes the 8-bit input stream bit-by-bit:
- **State-Based Field Extraction**: A small FSM tracks the bit position and routes the incoming bit to the appropriate serial exponent or mantissa shift register.
- **On-the-fly Bias Correction**: Exponent bias subtraction is performed using a bit-serial subtractor as the exponent bits arrive.

### 3.2. Bit-Serial Multiplier
The mantissa multiplication ($M_A \times M_B$) is implemented using a **Serial-Parallel** or **Purely Serial** multiplier:
- **Shift-and-Add**: A 1-bit full adder and a carry flip-flop perform the multiplication over multiple cycles.
- **Width**: For MXFP8 (E4M3), a 4-bit mantissa multiplication takes 16 cycles.

### 3.3. Serial Aligner (The Bit-Serial Shifter)
Alignment is the most area-intensive part of the parallel design due to the barrel shifter. In a bit-serial design:
- **Delayed Start**: The product stream is delayed by a number of cycles proportional to the required shift amount.
- **Counter-Based Alignment**: A counter tracks the alignment shift, and the bit-serial stream is gated or delayed until the correct bit position is reached.

### 3.4. Serial Accumulator
- **1-Bit Full Adder**: The aligned product bit-stream is added to the accumulator bit-stream (which is circulating in a shift register) using a single 1-bit full adder.
- **Carry Handling**: A single "Carry" D-Flip-Flop (DFF) stores the carry-out from bit $n$ to be used in bit $n+1$.

## 4. Operational Protocol (Extended)
A bit-serial implementation requires a significantly longer protocol than the current 41-cycle version.

| Phase | Parallel Cycles | Serial Cycles (Estimated) | Description |
|-------|-----------------|---------------------------|-------------|
| **Metadata** | 2 | 16 | Serial shift-in of Scales and Formats. |
| **Stream** | 32 | 256 - 1024 | 32 elements processed bit-serially. |
| **Summation** | 2 | 64 | Final carry propagation and scaling. |
| **Output** | 4 | 32 | Bit-serial shift-out of 32-bit result. |

## 5. Implementation Roadmap

### Phase 1: Serial Component Research
- **Step 1: Bit-Serial Library**: Develop a library of 1-bit primitives (Serial Adder, Serial Subtractor, Serial Comparator, Serial Multiplier).
- **Step 2: Shift-Register Memory**: Investigate using IHP SG13G2 latch-based or specialized DFF-based shift registers for area optimization.

### Phase 2: Serial Datapath Development
- **Step 3: Bit-Serial Multiplier Core**: Implement an 8-bit serial multiplier capable of handling both FP mantissas and INT8 values.
- **Step 4: The "Serial Aligner"**: Design a logic-delay-based alignment unit that replaces the 32-bit barrel shifter.
- **Step 5: Serial Accumulator**: Implement the 32-bit (or 40-bit for MX++) accumulator as a circulating shift register with a 1-bit adder.

### Phase 3: Control & Integration
- **Step 6: Serial FSM**: Replace the cycle counter with a more complex nested FSM (Block Cycle -> Element Cycle -> Bit Cycle).
- **Step 7: IO Interface**: Implement a bit-serial or nibble-serial interface to the host to match the internal datapath width.

### Phase 4: Verification & Benchmarking
- **Step 8: Bit-Serial Reference Model**: Create a cycle-accurate Python model of the serial execution.
- **Step 9: Area Comparison**: Compare the gate count of the `OCP-MX-SERIAL` against the `Ultra-Tiny` parallel configuration using `gate_analysis.py`.

## 6. Target Metrics
- **Area Goal**: < 500 gates (excluding shift registers).
- **Tile Target**: 1x1 Tiny Tapeout tile (Sky130 or IHP).
- **Frequency**: Optimized for 100MHz+ to compensate for high cycle counts.
