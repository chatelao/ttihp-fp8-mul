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

### 3.5. IO Interface (Hybrid Streaming)
To maintain backward compatibility with existing system integrations, the bit-serial variant maintains the **8-bit parallel IO interface** (`ui_in`, `uio_in`, `uo_out`).
- **Input Buffering**: Incoming bytes are captured into a 1-byte shift register and then processed bit-serially over 8 or more clock cycles.
- **Stretched Protocol**: The host must provide multiple clock cycles between data loads/stores. The internal FSM signals "ready" or simply expects a fixed `K` factor of cycles per element.

## 4. Operational Protocol (Stretched)
A bit-serial implementation requires a significantly longer protocol than the current 41-cycle version. The external interface remains 8-bit, but the time between elements is stretched by `SERIAL_K_FACTOR`.

| Phase | Parallel Cycles | Serial Cycles (K=32) | Description |
|-------|-----------------|----------------------|-------------|
| **Metadata** | 2 | 64 | Scales and Formats. |
| **Stream** | 32 | 1024 | 32 elements processed bit-serially. |
| **Summation** | 2 | 64 | Final carry propagation and scaling. |
| **Output** | 4 | 128 | 32-bit result shift-out (8 cycles per byte). |

## 5. Implementation Roadmap: Tiny-Serial

### Phase 1: Infrastructure & Baseline
- **Step 1: Tiny-Serial Variant**: Define a new architectural variant `Tiny-Serial` in CI/CE, initially mirroring `Ultra-Tiny`.
- **Step 2: Protocol Stretching**: Introduce `SUPPORT_SERIAL` and `SERIAL_K_FACTOR` in `src/project.v`. Update the FSM to spend more cycles in each state, maintaining the same 8-bit IO logic but with increased processing time.
- **Step 3: Testbench Adaptation**: Update `test/test.py` to handle the stretched protocol when `SUPPORT_SERIAL` is enabled.

### Phase 2: Incremental Serialisation
- **Step 4: Serial Multiplier Replacement**: Replace the parallel 8-bit multiplier with a bit-serial multiplier. Verify against `Ultra-Tiny` functional tests.
- **Step 5: Serial Aligner Replacement**: Replace the barrel shifter in `fp8_aligner.v` with a bit-serial alignment unit (delay-line based).
- **Step 6: Serial Accumulator Replacement**: Replace the parallel accumulator with a circulating shift register and 1-bit adder.

### Phase 3: Optimization & Hardening
- **Step 7: Shift-Register Memory**: Investigate using IHP SG13G2 latch-based or specialized DFF-based shift registers for area optimization.
- **Step 8: Gate Analysis**: Continuously monitor gate count using `test/gate_analysis.py` to ensure it stays below the `Ultra-Tiny` baseline.

## 6. Target Metrics
- **Area Goal**: < 500 gates (excluding shift registers).
- **Tile Target**: 1x1 Tiny Tapeout tile (Sky130 or IHP).
- **Frequency**: Optimized for 100MHz+ to compensate for high cycle counts.
