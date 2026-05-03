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

## 4. Operational Protocol (Stretched)
To maintain compatibility with the existing 8-bit streaming interface while allowing for bit-serial internal processing, the "Tiny-Serial" variant uses a **Stretched Protocol**.

Instead of changing the IO pins or the sequence of data, we scale the time between each 8-bit data load/unload by a factor $K$ (`SERIAL_K_FACTOR`).

- **Interface Stability**: The `ui_in`, `uio_in`, and `uo_out` ports remain 8-bit wide.
- **Timing Decoupling**: For every 1 cycle in the standard protocol, the Tiny-Serial variant uses $K$ internal cycles.
- **Element Rate**: 1 element is processed every $K$ clock cycles.

| Phase | Standard Cycles | Stretched Cycles (K=8) | Description |
|-------|-----------------|------------------------|-------------|
| **Metadata** | 3 | 24 | Shared scales, format, and MX+ metadata. |
| **Stream** | 32 | 256 | 32 elements processed with $K$ cycles per element. |
| **Summation** | 2 | 16 | Internal pipeline flush and alignment. |
| **Output** | 4 | 32 | Result shift-out (1 byte every $K$ cycles). |

## 5. Implementation Roadmap (Iterative Integration)
The "Tiny-Serial" variant is implemented as a gradual evolution from the "Ultra-Tiny" parallel baseline. This ensures that the unit is testable in CI/CE at every stage.

### Phase 1: Infrastructure & Protocol (Baseline)
- [x] **Step 1: Tiny-Serial Template**: Create the `Tiny-Serial` configuration in CI as a clone of `Ultra-Tiny`.
- [x] **Step 2: Stretched FSM**: Modify `src/project.v` to support `SUPPORT_SERIAL` and `SERIAL_K_FACTOR`. The FSM will "wait" $K$ cycles per protocol step.
- [x] **Step 3: Testbench Adaptation**: Update `test/test.py` to handle the variable timing based on `SERIAL_K_FACTOR`.

### Phase 2: Bit-Serial Module Integration
- [x] **Step 4.1: [Datapath] Serial Aligner & Accumulator**: Implement individual modules.
- [x] **Step 4.2: [Datapath] Serial LNS Multiplier**: Implement bit-serial multiplier.
- [x] **Step 4.3: [Integration] Serial Input Buffering**: Implement 8-bit shift registers to feed the serial datapath.
- [x] **Step 4.4: [Integration] Multiplier Swap**: Connect serial multiplier in the top-level serial path.
- [ ] **Step 4.5: [Integration] Aligner Swap**: Connect serial aligner and align timing.
- [ ] **Step 4.6: [Integration] Accumulator Swap**: Replace parallel accumulator in the serial path.
- [ ] **Step 4.7: [Integration] Serial-to-Parallel Handoff**: Connect serial accumulator to result capture.
- [ ] **Step 4.8: [Verification] Serial Parity**: Verify functional parity between parallel and serial variants.

### Phase 3: Area Optimization & Refinement
- [ ] **Phase C: Serial Integration (Advanced)**: Convert internal state registers to bit-serial shift registers.
- [ ] **Final Area Benchmarking**: Target < 500 gates for the complete bit-serial implementation.

## 6. Target Metrics
- **Area Goal**: < 500 gates (excluding shift registers).
- **Tile Target**: 1x1 Tiny Tapeout tile (Sky130 or IHP).
- **Frequency**: Optimized for 100MHz+ to compensate for high cycle counts.
