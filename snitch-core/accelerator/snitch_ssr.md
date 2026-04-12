# Snitch SSR (Stream Semantic Register)

The `snitch_ssr` module implements Stream Semantic Registers for the Snitch core. SSRs allow the core to stream data between memory and functional units (lanes) bypassing explicit load and store instructions. This significantly reduces instruction overhead for data-intensive loops.

## Overview

In the Snitch architecture, SSRs are configured to generate a sequence of memory addresses (e.g., for multi-dimensional loops). When a register is designated as an SSR, reading from it automatically triggers a memory load and returns the next element in the stream, while writing to it triggers a memory store.

## Key Components

### 1. Address Generator (`snitch_ssr_addr_gen`)
The address generator is responsible for calculating the sequence of addresses for memory accesses. It is configured via the `cfg_*` interface and supports:
- Multi-dimensional loops (up to a configured number of dimensions).
- Indirect addressing (using another SSR as an index).
- Intersection operations for sparse data.
- Element repetition.

### 2. Data FIFO (`fifo_v3`)
A FIFO buffers data between the memory (TCDM) and the lane.
- In **Read Mode**, it holds data fetched from memory until it is consumed by the lane.
- In **Write Mode**, it holds data written by the lane until it can be sent to memory.

Additionally, if `IsectMaster` is enabled, a separate 1-bit FIFO (`i_fifo_zero`) tracks "zero" flags for in-flight reads to support sparse intersection.

### 3. Memory Multiplexer (`tcdm_mux`)
When `Indirection` is enabled, the module instantiates a TCDM multiplexer to arbitrate between primary data requests and index requests used for indirect addressing.

### 4. Credit Counter (`snitch_ssr_credit_counter`)
The credit counter manages flow control by tracking the number of in-flight memory requests. It ensures that:
- Requests are only issued if there is space in the FIFO (Read Mode) or data available to send (Write Mode).
- The total number of outstanding requests does not exceed the configured `DataCredits`.

### 5. Repetition Counter
A simple hardware counter (`rep_q`) tracks how many times each data element should be repeated before moving to the next address. This is useful for certain algorithms (e.g., broadcasting a value or implementing stride patterns).

## Operational Modes

### Read Mode (Streaming from Memory)
- **Data Flow**: Memory (TCDM) -> FIFO -> Lane.
- **Trigger**: The core or a functional unit reads from the register associated with the SSR.
- **Credit Logic**:
    - `credit_take`: Incremented when a memory request is issued (`agen_valid & agen_ready`).
    - `credit_give`: Incremented when the lane consumes the final repetition of an element (`rep_enable & rep_done`).

### Write Mode (Streaming to Memory)
- **Data Flow**: Lane -> FIFO -> Memory (TCDM).
- **Trigger**: The core or a functional unit writes to the register associated with the SSR.
- **Credit Logic**:
    - `credit_take`: Incremented when a data element is popped from the FIFO and a write request is issued.
    - `credit_give`: Incremented when the memory system acknowledges the write (`data_rsp.p_valid`).

## Interfaces

| Interface | Type | Description |
|-----------|------|-------------|
| `clk_i`, `rst_ni` | Input | Clock and active-low asynchronous reset. |
| `cfg_*` | Input/Output | Configuration interface (REG_BUS) for programming loop parameters and control registers. |
| `lane_*` | Input/Output | Handshaked data interface to the functional units/register file. |
| `mem_*` | Output/Input | TCDM (Tightly Coupled Data Memory) interface for memory requests and responses. |
| `isect_*` | Output/Input | Interface for synchronization with other SSRs for intersection operations. |

## Direction Reversal

When the SSR switches between Read and Write modes (e.g., by changing the `write` bit in the configuration), it must ensure that any in-flight data is properly handled to prevent stream corruption.
- The `agen_flush` signal is asserted when a direction change is detected.
- It prevents new requests from being issued until the credit counter indicates that all in-flight transactions have completed (`credit_full`).

## Configuration (`snitch_ssr_pkg`)

The behavior of the SSR is highly parameterized via the `ssr_cfg_t` structure, which includes:
- `NumLoops`: Number of supported loop dimensions.
- `DataCredits`: Maximum number of outstanding memory requests.
- `Indirection`: Whether indirect addressing is supported.
- `IsectMaster/Slave`: Configuration for hardware-assisted sparse intersection.
