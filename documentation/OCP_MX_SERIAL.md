# Concept: Bit-Serial OCP MX MAC Unit (OCP-MX-SERIAL)

## 1. Introduction
While the current streaming implementation of the OCP MX MAC unit is optimized for throughput and fits within a 1x2 Tiny Tapeout tile, certain ultra-constrained applications (e.g., thousands of units in a large-scale systolic array or 1x1 tile targets with high feature sets) require even smaller footprints.

Inspired by **SERV** (the award-winning bit-serial RISC-V core), this concept proposes a **purely bit-serial implementation** of the OCP MX specification. By processing data one bit at a time, we can trade off latency for a significant reduction in gate count and routing congestion.

## 2. Core Philosophy: The SERV Approach
The fundamental principle of SERV is that any N-bit operation can be decomposed into N 1-bit operations over N clock cycles. For an OCP MX MAC unit, this means:
- **Registers as Shift Registers**: Operands, exponents, and the accumulator are stored in shift registers or small bit-serial memories.
- **1-Bit Datapath**: All arithmetic (addition, multiplication, shifting) is performed using 1-bit full adders and minimal control logic.
- **Latency-Area Tradeoff**: An 8-bit multiplication that takes 1 cycle in a parallel multiplier will take ~64 cycles in a bit-serial multiplier, but use ~1/10th of the area.

## 3. Interface Consistency
To maintain compatibility with existing host controllers and the Tiny Tapeout 8-bit I/O, the **external interface remains identical**:
- **8-bit `ui_in`**: Still used for Scales and Element data.
- **8-bit `uio_in`**: Still used for Control/Format and Element data.
- **8-bit `uo_out`**: Still used for the 32-bit serialized result.

The only change from the outside is the **timing**: the number of clock cycles between data loads or stores increases by a factor of $K$ (where $K$ is the serialization factor, typically 8 for bit-serial operations).

## 4. Bit-Serial Architecture

### 4.1. Serial Decoder
Instead of a parallel decoder that unpacks S, E, and M fields in one cycle, the serial decoder processes the 8-bit input stream bit-by-bit:
- **State-Based Field Extraction**: A small FSM tracks the bit position and routes the incoming bit to the appropriate serial exponent or mantissa shift register.
- **On-the-fly Bias Correction**: Exponent bias subtraction is performed using a bit-serial subtractor as the exponent bits arrive.

### 4.2. Bit-Serial Multiplier
The mantissa multiplication ($M_A \times M_B$) is implemented using a **Serial-Parallel** or **Purely Serial** multiplier:
- **Shift-and-Add**: A 1-bit full adder and a carry flip-flop perform the multiplication over multiple cycles.
- **Width**: For MXFP8 (E4M3), a 4-bit mantissa multiplication takes 16 cycles.

### 4.3. Serial Aligner (The Bit-Serial Shifter)
Alignment is the most area-intensive part of the parallel design due to the barrel shifter. In a bit-serial design:
- **Delayed Start**: The product stream is delayed by a number of cycles proportional to the required shift amount.
- **Counter-Based Alignment**: A counter tracks the alignment shift, and the bit-serial stream is gated or delayed until the correct bit position is reached.

### 4.4. Serial Accumulator
- **1-Bit Full Adder**: The aligned product bit-stream is added to the accumulator bit-stream (which is circulating in a shift register) using a single 1-bit full adder.
- **Carry Handling**: A single "Carry" D-Flip-Flop (DFF) stores the carry-out from bit $n$ to be used in bit $n+1$.

## 5. Operational Protocol (Extended)
A bit-serial implementation requires a significantly longer protocol than the current 41-cycle version.

| Phase | Parallel Cycles | Serial Cycles (Estimated) | Description |
|-------|-----------------|---------------------------|-------------|
| **Metadata** | 2 | 16 | Serial shift-in of Scales and Formats. |
| **Stream** | 32 | 256 - 1024 | 32 elements processed bit-serially. |
| **Summation** | 2 | 64 | Final carry propagation and scaling. |
| **Output** | 4 | 32 | Bit-serial shift-out of 32-bit result. |

## 6. Implementation Roadmap: "Tiny-Serial" Variant

### Step 0: CI/CE Infrastructure (Baseline)
- [ ] Add `Tiny-Serial` to `.github/workflows/test.yaml` and `gowin.yaml`.
- [ ] Initialize as a clone of `Ultra-Tiny` (Parallel) with `SUPPORT_SERIAL=1` and `SERIAL_K_FACTOR=1`.
- [ ] Update `test/test.py` to support variable clock intervals between elements.

### Step 1: Bit-Serial Component Library
- [ ] Implement `serial_adder.v`, `serial_sub.v`, and `serial_mul.v`.
- [ ] Verify 1-bit components using cocotb unit tests.

### Step 2: Serial Multiplier Integration
- [ ] Integrate bit-serial multiplier into `src/project.v`.
- [ ] Increase `SERIAL_K_FACTOR` to 8 for the multiplication phase.
- [ ] Maintain parallel alignment and accumulation for initial verification.

### Step 3: Serial Aligner & Shifter
- [ ] Implement logic-delay-based alignment.
- [ ] Replace the 32-bit barrel shifter with the serial aligner.

### Step 4: Serial Accumulator & Decoder
- [ ] Implement the 32-bit/40-bit accumulator as a circulating shift register.
- [ ] Implement bit-by-bit format decoding.

### Step 5: Optimization & Hardening
- [ ] Compare gate count against `Ultra-Tiny` (< 500 gate goal).
- [ ] Run through GDSII flow to verify 1x1 tile density.

## 7. Target Metrics
- **Area Goal**: < 500 gates (excluding shift registers).
- **Tile Target**: 1x1 Tiny Tapeout tile (Sky130 or IHP).
- **Frequency**: Optimized for 100MHz+ to compensate for high cycle counts.
