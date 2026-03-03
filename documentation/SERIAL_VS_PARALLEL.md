# Analysis: 1x Parallel vs. 4x Serial OCP MX Implementation

This document provides a comparative analysis of two architectural approaches for implementing the OCP MX MAC unit in area-constrained silicon (e.g., Tiny Tapeout).

## 1. Architectural Definitions

| Feature | 1x OCP MX Parallel (Ultra-Tiny) | 4x OCP MX Serial (Tiny-Serial) |
|---|---|---|
| **Parallelism** | Single 8-bit streaming lane | Four independent 1-bit serial lanes |
| **Datapath** | N-bit combinatorial (Multiplier, Aligner) | 1-bit sequential (Full Adder, Counter) |
| **Interface** | 8-bit streaming (Standard) | 1-bit streaming (Snooping/Bit-Serial) |
| **Internal Timing** | Single-cycle datapath operations | Multi-cycle (K=8) bit-serial operations |

---

## 2. Total Die Size & Area Analysis

The die size for both solutions is comparable (~2000-2500 gates), but the distribution of area costs differs significantly.

### 2.1. 1x OCP MX Parallel (Ultra-Tiny)
- **Total Gates**: **~2,057 Gates**
- **Reasoning for Overhead**:
    - **Barrel Shifter (~500 Gates)**: The product aligner is the largest single component. It requires a massive multiplexer tree to support shifts of up to 40 bits in a single cycle.
    - **Parallel Multiplier (~350 Gates)**: The 8x8 (or 4x4) multiplier uses a Wallance/Dadda tree or array structure, consuming area for numerous half/full adders in a combinatorial block.
    - **Parallel Accumulator (~300 Gates)**: A 24-bit or 32-bit register and a corresponding parallel adder.
    - **Routing Congestion**: High. Routing 32-bit buses through the aligner and accumulator increases "white space" and routing overhead.

### 2.2. 4x OCP MX Serial (Tiny-Serial)
- **Total Gates**: **~2,400 Gates** (4 units @ ~600 gates each)
- **Reasoning for Overhead**:
    - **Shift Registers (~400 Gates/Unit)**: Instead of combinatorial logic, area is dominated by D-Flip-Flops (DFFs) used as shift registers for operands and the accumulator.
    - **Datapath (< 50 Gates/Unit)**: The arithmetic is performed by a single 1-bit full adder and a carry-flop. This is the most area-efficient datapath possible.
    - **Control Logic (~150 Gates/Unit)**: Significant overhead compared to the datapath. Requires bit-counters (5-bit for elements, 3-bit for sub-cycles) and state tracking for field extraction.
    - **Routing Congestion**: Very Low. Signals are mostly local or 1-bit wide, allowing for much denser placement and higher utilization of the silicon area.

---

## 3. Performance: Duration Analysis

Performance is measured in clock cycles required to complete OCP MX blocks (32 elements per block).

### 3.1. Duration for 1 Calculation (1 Block / 32 Elements)
- **1x Parallel**: **41 Cycles**
    - 32 cycles for streaming + 9 cycles for setup/scaling/output.
- **4x Serial**: **328 Cycles** (per unit)
    - With $K=8$, each protocol step takes 8 cycles. 41 steps * 8 = 328 cycles.
- **Winner**: **1x Parallel** (8x faster for a single block).

### 3.2. Duration for 128 Calculations (128 Blocks)
- **1x Parallel**: **5,248 Cycles**
    - $128 \times 41 = 5,248$ cycles.
- **4x Serial**: **10,496 Cycles**
    - 128 blocks are distributed across 4 units (32 blocks per unit).
    - $32 \times 328 = 10,496$ cycles.
- **Efficiency Gap**: The serial implementation is ~2x slower in total throughput for large batches, despite using similar area. This is because bit-serial logic spends a higher percentage of cycles on "effective work" vs. setup but suffers from the $K$ scaling factor.

---

## 4. Power & Energy Consumption

| Metric | 1x Parallel | 4x Serial | Reasoning |
|---|---|---|---|
| **Static Power** | Baseline | ~1.1x | Higher DFF count in 4x serial units. |
| **Dynamic Power** | High | **Low (per unit)** | Parallel implementation suffers from heavy **glitching** in the barrel shifter and multiplier trees. |
| **Energy per Calc** | Baseline | **~0.6x - 0.8x** | Bit-serial units have almost zero glitching. Every transition is productive. Total energy is lower despite longer duration. |

### Reasoning:
1.  **Glitching**: In the parallel aligner, a single change at the input can cause thousands of intermediate transitions as signals propagate through the MUX tree. In the bit-serial unit, there is no tree; signals propagate through single gates per cycle.
2.  **Clock Gating**: Serial units are easier to clock-gate at a granular level. If only 2 of 4 units are needed, the others consume almost zero power.
3.  **$F_{max}$ Scaling**: The 4x Serial implementation can likely run at a much higher clock frequency ($F_{max}$) because its critical path is just a single 1-bit adder. This allows it to reclaim performance through frequency scaling.

---

## 5. Summary: Disadvantages & Advantages

### 5.1. 1x OCP MX Parallel
*   **Advantages**:
    *   **Lowest Latency**: Ideal for real-time applications where single-result speed is critical.
    *   **Protocol Simplicity**: Matches the standard OCP MX streaming protocol 1:1.
*   **Disadvantages**:
    *   **Routing Hardness**: Becomes difficult to fit into 1x1 tiles as features (like MX+) are added.
    *   **Timing Closure**: High-width barrel shifters limit the maximum frequency.

### 5.2. 4x OCP MX Serial
*   **Advantages**:
    *   **Area Granularity**: Can be tiled into irregular shapes or distributed around a CPU core (e.g., SERV).
    *   **High Frequency**: Can operate at 2-3x the frequency of parallel units, potentially closing the performance gap.
    *   **Energy Efficiency**: Superior for battery-powered or thermal-constrained environments.
*   **Disadvantages**:
    *   **High Latency**: 8x higher latency for the first result.
    *   **Control Complexity**: Requires sophisticated synchronization to manage 4 independent bit-streams.

## 6. Conclusion
For a **high-throughput systolic array**, the **1x Parallel** implementation is superior due to its better cycles-per-element efficiency. However, for **integration into a bit-serial CPU (like SERV)** or for **ultra-low-power IoT edge devices**, the **4x Serial** approach provides better energy-area scaling and easier timing closure.

## 7. Analysis: 2-bit Digit-Serial vs. 1-bit Bit-Serial

As designs scale, a 1-bit bit-serial approach (Radix-2) may become a performance bottleneck, while a full parallel approach remains too costly in terms of routing or peak power. A **2-bit digit-serial (Radix-4)** implementation offers a middle ground.

### 7.1. Architectural Overview
- **1-bit (Radix-2)**: Processes 1 bit per cycle. Uses a single full-adder for additions and a shift-and-add multiplier that takes $N$ cycles for an $N$-bit operand.
- **2-bit (Radix-4)**: Processes 2 bits per cycle. Requires a 2-bit adder (or two 1-bit adders) and a more complex digit-multiplier. Registers shift 2 bits at a time.

### 7.2. Comparative Metrics (Estimated)

| Metric | 1-bit Bit-Serial | 2-bit Digit-Serial | Reasoning |
|---|---|---|---|
| **Gate Count** | Baseline (~2,100) | **~1.25x - 1.35x** | Increased complexity in the 2-bit adder and muxing for 2-bit shifts. |
| **Cycle Count (K=8)** | 328 Cycles | **164 Cycles** | Throughput is doubled as 2 bits are processed per clock. |
| **Throughput** | 1.0x | **2.0x** | Completion time is halved. |
| **Routing Density** | Very Low | **Low-Medium** | 2-bit buses are still very manageable compared to 32-bit parallel buses. |
| **Energy Efficiency** | High | **Superior** | While peak power is higher, the "leakage energy" (static power $\times$ time) is significantly reduced due to faster completion. |

### 7.3. Why Choose 2-bit Digit-Serial?
1.  **Optimal Energy-Delay Product (EDP)**: 2-bit serial often hits the "sweet spot" where the reduction in execution time outweighs the modest increase in area/power.
2.  **Frequency Matching**: If the internal fabric can run at 2x the IO frequency, a 2-bit serial unit can match a 4-bit parallel unit's throughput while maintaining the benefits of serial routing.
3.  **Graceful Scaling**: It provides a path for scaling performance in 1x1 tiles without jumping to a full parallel datapath that might fail placement or timing.

### 7.4. Implementation Complexity
The transition from 1-bit to 2-bit requires:
- **Modified Counters**: The bit-counters must increment by 2 or handle half the cycle count.
- **Digit-Serial Multiplier**: Instead of a simple `AND` gate and shift-and-add, a radix-4 multiplier (e.g., using Modified Booth Encoding or a small 2xN multiplier) is needed.
- **Wider Shift Registers**: DFFs remain the same, but the connectivity must support 2-bit shifts (Q -> D of two stages away).
