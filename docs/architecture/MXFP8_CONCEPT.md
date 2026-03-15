# Concept: Streaming MX MAC Unit for Tiny Tapeout

## 1. Introduction
The scaling of Deep Learning models necessitates efficient numerical representations to overcome the "Memory Wall". The **OCP Microscaling Formats (MX) Specification v1.0** introduces a block-based scaling approach that significantly reduces memory bandwidth and hardware complexity. This concept outlines the implementation of an MX-compatible Multiply-Accumulate (MAC) unit supporting various floating-point and integer formats within the strict constraints of a single **1x1 Tiny Tapeout tile** (Sky130/IHP SG13G2).

## 2. Numerical Representation: OCP MX
The implementation supports multiple **OCP MX** formats, including MXFP8, MXFP6, MXFP4, and MXINT8, all sharing a common block scaling factor.

- **Shared Scale**: UE8M0 (8-bit unsigned biased exponent, Bias 127, power-of-two scaling).
- **Element Formats**:
  - **MXFP8**: E4M3 (Bias 7) and E5M2 (Bias 15).
  - **MXFP6**: E3M2 (Bias 3) and E2M3 (Bias 1).
  - **MXFP4**: E2M1 (Bias 1).
  - **MXINT8**: Standard and Symmetric 8-bit signed integers.

### Bitwise Layouts
All formats are aligned to the lower bits of the 8-bit input wires during the `STREAM` phase.

#### E4M3 (8-bit MXFP8)
| Bit | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|:---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **Field** | S | E3 | E2 | E1 | E0 | M2 | M1 | M0 |
- **S**: Sign bit. **E[3:0]**: Exponent (Bias 7). **M[2:0]**: Mantissa.

#### E5M2 (8-bit MXFP8)
| Bit | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|:---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **Field** | S | E4 | E3 | E2 | E1 | E0 | M1 | M0 |
- **S**: Sign bit. **E[4:0]**: Exponent (Bias 15). **M[1:0]**: Mantissa.

#### E3M2 (6-bit MXFP6)
| Bit | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|:---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **Field** | - | - | S | E2 | E1 | E0 | M1 | M0 |
- **S**: Sign bit. **E[2:0]**: Exponent (Bias 3). **M[1:0]**: Mantissa.

#### E2M3 (6-bit MXFP6)
| Bit | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|:---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **Field** | - | - | S | E1 | E0 | M2 | M1 | M0 |
- **S**: Sign bit. **E[1:0]**: Exponent (Bias 1). **M[2:0]**: Mantissa.

#### E2M1 (4-bit MXFP4)
| Bit | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|:---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **Field** | - | - | - | - | S | E1 | E0 | M0 |
- **S**: Sign bit. **E[1:0]**: Exponent (Bias 1). **M[0]**: Mantissa.

#### MXINT8 (8-bit)
| Bit | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|:---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **Field** | S | V6 | V5 | V4 | V3 | V2 | V1 | V0 |
- **S**: Sign bit. **V[6:0]**: Value (Two's complement).
- **INT8_SYM**: Symmetric range where -128 is clamped to -127.

#### Shared Scale: UE8M0 (8-bit)
| Bit | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|:---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **Field** | X7 | X6 | X5 | X4 | X3 | X2 | X1 | X0 |
- **X[7:0]**: 8-bit Unsigned Biased Exponent (Bias 127).

### Numerical Semantics
- **Block Size ($k$)**: 32 elements.
- **Mathematical Formula**:
  - **FP Formats**: $V_i = (-1)^{S_i} \times 2^{E_i - \text{Bias}} \times (1 + M_i) \times 2^{X-127}$
  - **INT Formats**: $V_i = (\text{Integer}_i \times 2^{-6}) \times 2^{X-127}$ (As per OCP MX v1.0, INT8 has an implicit $2^{-6}$ scale).
- **Subnormals**: Supported in all floating-point element types per OCP MX v1.0.
- **Special Values**: The unit prioritizes saturation for out-of-range values. E5M2 supports IEEE-style Infinities and NaNs, while other formats utilize the full range for finite numbers or specialized NaN encodings as per OCP MX v1.0.

### 2.1. Optimization: FP4 Vector Packing
For the 4-bit **MXFP4** format, the 8-bit input wires (`ui_in`, `uio_in`) carry **two elements per cycle** when "Packed Mode" is enabled.
- **Implementation**: Enabled via `uio_in[6]=1` in Cycle 1 and the `SUPPORT_VECTOR_PACKING` parameter.
- **Cycle Reduction**: The `STREAM` phase is reduced from 32 cycles to 16 cycles, resulting in a **25-cycle** (if pipelining off) or **higher** (if pipelining on) total protocol.
- **Hardware Impact**: Achieving this $2\times$ throughput increase utilizes a second parallel multiplier-accumulator path (dual-lane datapath). This is optional and can be disabled via parameters to save area in "Tiny" builds.
- **Compliance**: The OCP MX v1.0 specification requires a block size ($k$) of 32. By processing two 4-bit elements per 8-bit input, the unit maintains the $k=32$ block size while doubling throughput.

## 3. Architecture: Operand Streaming
To fit within the ~320 D-Flip-Flop (DFF) budget of a 1x1 tile, the design employs **Temporal Multiplexing (Operand Streaming)**.

### 3.1. I/O Protocol (41-Cycle Sequence)
The unit communicates with a host using a strictly timed protocol:

| Phase | Cycles | Input (`ui_in`) | Input (`uio_in`) | Output (`uo_out`) |
|-------|--------|-----------------|------------------|-------------------|
| **IDLE** | 0 | - | - | 0 |
| **LOAD_SCALE** | 1 | Scale $X_A$ | Format A / NC | 0 |
| **LOAD_SCALE** | 2 | Scale $X_B$ | Format B | 0 |
| **STREAM** | 3-34 | Element $A_i$ | Element $B_i$ | 0 |
| **PIPELINE** | 35-36 | - | - | 0 |
| **OUTPUT** | 37-40 | - | - | Accumulator[byte] |

#### Detailed I/O Bit Mapping

**Table 1: Input `ui_in` (Primary)**
| Phase | Cycles | Bits [7:0] | Function | Description |
|-------|--------|------------|----------|-------------|
| **IDLE** | 0 | `SXXXXXXX` | **Fast Start** | Bit [7]=1 skips LOAD_SCALE cycles. |
| **LOAD_SCALE** | 1 | `X_A[7:0]` | **Scale A** | Shared UE8M0 scale for Tensor A. |
| **LOAD_SCALE** | 2 | `X_B[7:0]` | **Scale B** | Shared UE8M0 scale for Tensor B. |
| **STREAM** | 3-34 | `A_i[7:0]` | **Element A** | MX element (aligned to lower bits). |
| **PIPELINE** | 35-36 | `XXXXXXXX` | N/A | |
| **OUTPUT** | 37-40 | `XXXXXXXX` | N/A | |

**Table 2: Input `uio_in` (Bidirectional)**

![OCP MX Hardware Config Bitfield](https://svg.wavedrom.com/%7B%22reg%22%3A%20%5B%7B%22name%22%3A%20%22Format%20A%22%2C%20%22bits%22%3A%203%7D%2C%20%7B%22name%22%3A%20%22Rounding%22%2C%20%22bits%22%3A%202%7D%2C%20%7B%22name%22%3A%20%22Overflow%22%2C%20%22bits%22%3A%201%7D%2C%20%7B%22name%22%3A%20%22Packed%22%2C%20%22bits%22%3A%201%7D%2C%20%7B%22name%22%3A%20%22MX%2B%20Enable%22%2C%20%22bits%22%3A%201%7D%5D%2C%20%22config%22%3A%20%7B%22bits%22%3A%208%7D%7D)
*Source: [docs/diagrams/OCP_MX_CONFIG_BITFIELD.json](../diagrams/OCP_MX_CONFIG_BITFIELD.json)*

| Phase | Cycles | Bits [7:0] | Function | Description |
|-------|--------|------------|----------|-------------|
| **IDLE** | 0 | `XXXXXXXX` | N/A | |
| **LOAD_SCALE** | 1 | `XPOWWFFF` | **Format A/NC** | [2:0] Format A, [4:3] Round, [5] Ovfl, [6] Packed. |
| **LOAD_SCALE** | 2 | `XXXXXFFF` | **Format B** | [2:0] Format B (if mixed precision enabled). |
| **STREAM** | 3-34 | `B_i[7:0]` | **Element B** | MX element (aligned to lower bits). |
| **PIPELINE** | 35-36 | `XXXXXXXX` | N/A | |
| **OUTPUT** | 37-40 | `XXXXXXXX` | N/A | |

#### Table 4: Supported Formats
| Format ID (`FFF`) | Name | Type | Bits | Sign | Exponent | Mantissa | Bias |
|---|---|---|---|---|---|---|---|
| `000` | E4M3 | MXFP8 | 8 | [7] | [6:3] | [2:0] | 7 |
| `001` | E5M2 | MXFP8 | 8 | [7] | [6:2] | [1:0] | 15 |
| `010` | E3M2 | MXFP6 | 6 | [5] | [4:2] | [1:0] | 3 |
| `011` | E2M3 | MXFP6 | 6 | [5] | [4:3] | [2:0] | 1 |
| `100` | E2M1 | MXFP4 | 4 | [3] | [2:1] | [0] | 1 |
| `101` | INT8 | MXINT8 | 8 | [7] | N/A | [6:0] | N/A |
| `110` | INT8_SYM | MXINT8 | 8 | [7] | N/A | [6:0] | N/A |

#### Table 5: Numerical Control Bits (Cycle 1)
| Bits | Name | Description |
|---|---|---|
| [2:0] | Format | Format Selection (see Table 4). |
| [4:3] | Rounding | 00: TRN (Truncate), 01: CEIL (Round up), 10: FLOOR (Round down), 11: RNE (Ties to Even). |
| [5] | Overflow | 0: SAT (Saturation), 1: WRAP (Wrapping). |

**Table 3: Output `uo_out` (Accumulator Serialization)**
| Phase | Cycle | Bits [7:0] | Content |
|-------|-------|------------|---------|
| **OUTPUT** | 37 | `Acc[31:24]` | Byte 3 (MSB) |
| **OUTPUT** | 38 | `Acc[23:16]` | Byte 2 |
| **OUTPUT** | 39 | `Acc[15:8]` | Byte 1 |
| **OUTPUT** | 40 | `Acc[7:0]` | Byte 0 (LSB) |

### 3.2. Hardware/Software Co-Design
The hardware computes the dot product of the scaled elements but factors out the shared scales to minimize gate count:
$$C = \left( \sum_{i=1}^{32} \text{FP}(A_i) \times \text{FP}(B_i) \right) \times 2^{(X_A-127) + (X_B-127)}$$
The ASIC performs the summation and the intermediate exponent arithmetic. The final scaling by the shared factors is performed by the host software (default) or hardware-accelerated in later stages.

## 4. Microarchitecture
### 4.1. Datapath
- **Sign Logic**: $S_{res} = S_A \oplus S_B$ (for FP) or signed multiplication (for INT).
- **Exponent Path**: Unified logic for variable exponent ranges and biases.
- **Mantissa Multiplier**: 4x4-bit integer multiplier (extended to 8x8 for INT8).
- **Alignment Shifter**: A barrel shifter aligns the product to a 32-bit fixed-point format (bit 8 = $2^0$) with saturation logic.
- **Accumulator**: A 32-bit signed register stores the running sum.

### 4.2. Control Logic
- **Finite State Machine (FSM)**: Manages the protocol, including format and scale sampling.

## 5. Resource Estimation (1x1 Tile)
- **D-Flip-Flops (DFFs)**: ~150 DFFs (approx. 45% of 1x1 tile limit).
- **Combinational Logic**: 8x8 Multiplier + Barrel Shifter + 32-bit Adder.
- **Total Area**: Optimized for IHP SG13G2 1x1 tile.

## 6. Gaps and Future Work

This section identifies features described in the concept that are currently unimplemented or require further refinement.

### GAP: NaN and Infinity Propagation
- [x] **Full Support for Special Values**: While the design supports subnormals and prioritizes saturation, comprehensive propagation of IEEE-754 NaNs and Infinities (specifically for E5M2) and OCP-specified NaN encodings for other formats is fully implemented in the datapath and sticky registers.

### GAP: Parameterized Block Size
- [ ] **Dynamic Block Size**: The current implementation is optimized for a fixed block size of $k=32$ (or $k=16$ in packed mode). Future versions should allow parameterization of the block size via Verilog parameters.

### GAP: Hardware-in-the-Loop (HIL) and Silicon Validation
- [ ] **Physical Verification**: Functional verification on FPGA (HIL) and final silicon validation on the Tiny Tapeout demo board are pending fabrication and assembly.

