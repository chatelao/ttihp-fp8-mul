# Google TPU v7 TensorCore Architecture

## Overview
The **Google TPU v7 TensorCore** (introduced in 2026) is the primary compute engine of Google's seventh-generation AI accelerator. Building upon the "Trillium" (v6) architecture, the TPU v7 is specifically optimized for Large Language Model (LLM) serving and multi-modal AI workloads.

A defining feature of the v7 architecture is its native hardware support for the **OCP Microscaling (MX) Formats (v1.0)** and the **MX+ extension**. This allows the TensorCore to process ultra-low precision data (e.g., 4-bit MXFP4) while maintaining high model accuracy by providing extended mantissa precision for "Block Max" (BM) outlier elements.

## Architecture Diagram

![Google TPU v7 TensorCore Architecture](https://www.plantuml.com/plantuml/proxy?cache=no&src=https://raw.githubusercontent.com/chatelao/ttihp-fp8-mul/main/docs/diagrams/GOOGLE_V7_TPU_TENSORCORE.PUML)

*Source: [docs/diagrams/GOOGLE_V7_TPU_TENSORCORE.PUML](../diagrams/GOOGLE_V7_TPU_TENSORCORE.PUML)*

## 4-Level Circuit Hierarchy
The TPU v7 TensorCore is organized into a nested hierarchy to manage complexity and data distribution:

1.  **Level 1: TPU v7 Core (TensorCore)**
    - The top-level processing tile containing the compute units, high-bandwidth memory (HBM) interfaces, and the **Vector Processing Unit (VPU)** for activation functions.
    - Manages the top-level control flow and synchronization between multiple MXUs.

2.  **Level 2: Matrix Multiply Unit (MXU)**
    - A specialized hardware block designed for high-throughput matrix-matrix multiplication.
    - Contains the local memory (SRAM) for weight storage and the systolic control logic.
    - Aggregates results from multiple PE arrays.

3.  **Level 3: PE Array (Systolic Grid)**
    - A grid of Processing Elements (PEs) typically arranged in a 128x128 or 256x256 configuration.
    - Implements the **Weight-Stationary** dataflow, where weights are pre-loaded into the grid and activations stream through.

4.  **Level 4: Processing Element (PE)**
    - The fundamental arithmetic unit at the circuit level.
    - Contains the **MX+ Decoder**, a 4-bit/8-bit multiplier core, a high-precision aligner, and a 32-bit local accumulator.
    - The PE is capable of dynamically switching between standard OCP MX and MX+ modes based on the Block Max index metadata.

## Vector Processing Unit (VPU)
The **Vector Processing Unit (VPU)** is a high-performance SIMD engine within the TPU v7 Core designed to handle non-linear operations that are not suited for the systolic MXU. While the MXU excels at matrix-matrix multiplication, the VPU provides the flexibility required for the diverse set of vector operations found in modern Transformer architectures.

### Key Responsibilities:
-   **Activation Functions**: Implementation of computationally expensive non-linearities such as **GeLU**, **ReLU**, **SwiGLU**, and **Softmax**.
-   **Normalization**: Performs high-precision **LayerNorm** and **RMSNorm** operations. It typically operates on 32-bit intermediate results to maintain numerical stability before requantizing to MX formats.
-   **Element-wise & Vector Operations**: Supports vector-vector addition, multiplication, and scaling, which are critical for residual connections and attention mask application.
-   **Transposition & Permutation**: Handles data layout transformations required between different layers or attention heads.

### Integration with MX+ Pipeline:
The VPU acts as the "post-processor" for the MXU's systolic grid. Once the 32-bit partial sums are reduced and finalized (including the high-precision MX+ Block Max contributions), they are streamed into the VPU. The VPU applies the necessary shared scaling factors, performs the activation or normalization, and then uses a high-speed hardware quantizer to convert the results back into OCP MX (MXFP4/6/8) formats for storage in HBM or for use as activations in the next layer.

## Dataflow
The TPU v7 utilizes a **Weight-Stationary** systolic dataflow optimized for the MX protocol:

-   **Weights**: Pre-loaded from HBM into the PE Array. Each PE holds a single weight value (or a packed pair in MXFP4 mode) for the duration of a matrix operation.
-   **Activations**: Streamed horizontally through the grid. Each PE performs a Multiply-Accumulate (MAC) operation using the local weight and the incoming activation.
-   **Partial Sums**: Reduced vertically through the grid. Each PE adds its local product to the partial sum received from the PE above it and passes the updated sum to the PE below.
-   **Output**: The final dot product results are collected at the bottom of the grid, where they are aligned and scaled according to the OCP MX shared scaling factors before being passed to the VPU.
