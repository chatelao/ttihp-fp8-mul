# NVIDIA 5th Generation Tensor Cores (Blackwell Architecture)

## Overview
The NVIDIA Blackwell architecture introduces the **5th Generation Tensor Cores**, designed to accelerate the most demanding AI and high-performance computing (HPC) workloads. A key innovation in this generation is the native support for ultra-low precision data formats, specifically **FP4** and **FP6**, which significantly increase throughput and efficiency for Large Language Model (LLM) serving.

## Architecture Diagram

![NVIDIA 5th Gen Tensor Core (Blackwell) Architecture](https://www.plantuml.com/plantuml/proxy?cache=no&src=https://raw.githubusercontent.com/chatelao/ttihp-fp8-mul/main/documentation/BLACKWELL_TENSOR_CORE.PUML)

*Source: [documentation/BLACKWELL_TENSOR_CORE.PUML](BLACKWELL_TENSOR_CORE.PUML)*

## Key Features
- **Native FP4 and FP6 Support**: Blackwell Tensor Cores provide native hardware acceleration for 4-bit and 6-bit floating-point formats, doubling the throughput compared to FP8.
- **Microscaling (MX) Compatibility**: The architecture is designed to work seamlessly with **OCP Microscaling (MX) formats**, utilizing block-based scaling to maintain high numerical accuracy at low bit-widths.
- **Increased Throughput**: Each Tensor Core can complete one FP4 `mma.m16n8k64` operation every 16 cycles, delivering massive performance gains for matrix multiply-and-accumulate operations.
- **Improved Efficiency**: By reducing the bit-width of weights and activations, Blackwell minimizes memory bandwidth pressure and power consumption while maintaining model performance.

## Architecture & Hierarchy
The Blackwell Tensor Core follows a structured hierarchy to manage parallel data processing:
1.  **Tensor Core**: The top-level unit, where each warp executes on a single Tensor Core containing **32 Dot Product Engines (DPEs)**.
2.  **Octet**: A subdivision of the Tensor Core. A warp consists of **4 Octets**.
3.  **Threadgroup**: Each Octet contains **2 Threadgroups**. Four threads form a threadgroup that utilizes **4 DPEs**.
4.  **Dot Product Engine (DPE)**: The fundamental compute unit. Each DPE processes 16 FP4 input pairs per cycle (one MXFP4 block pair every two cycles).

## Dataflow
1.  **Register File**: Input fragments for matrices A and B are stored in the register file.
2.  **Intermediate Buffers**: Threads collaboratively load operand matrices from registers into intermediate buffers.
3.  **Dot Product Engine (DPE)**:
    - **Vector Multiplier**: Performs element-wise multiplication of the input pairs.
    - **Adder Tree**: Conducts multi-level additions to produce the partial dot product result.
4.  **Accumulator**: The result from the adder tree is accumulated with the bias or previous sum.
5.  **Normalization & Conversion**: The accumulated result (typically in FP32) is normalized and converted to the desired output format.
6.  **Write-back**: The final result is written back to the register file.
