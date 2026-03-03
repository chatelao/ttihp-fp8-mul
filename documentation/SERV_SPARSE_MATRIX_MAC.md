# SERV Sparse Matrix MAC Optimization Proposal

In sparse matrix multiplications (SpMM), the primary challenge is "irregular access"—you are often multiplying a sparse matrix (stored as values and indices) by a dense vector. This requires fetching data from memory locations that aren't next to each other.
Both AVX10 and RVV handle this using Gather and Scatter instructions, but they do so with different architectural styles.

## Intel AVX10 (and AVX-512)
AVX10 relies on "VSIB" (Vector Sparse Index Base) addressing. It uses a base address and a vector of offsets to pull data into a single register.

### Best Instructions:
* **VPGATHERDD / VPGATHERQD**: These "Gather" instructions load multiple non-contiguous data elements into a single ZMM register.
* **VPSCATTERDD / VPSCATTERQD**: "Scatter" the results back to non-contiguous memory.
* **Compress/Expand**: Instructions like `VPCOMPRESSD` and `VPEXPANDD` are unique to the AVX-512/AVX10 lineage. They are incredibly useful for filtering out zero elements from a dense row to create a sparse representation on the fly.

**The "Secret Sauce"**: AVX10's Mask Registers (k0–k7). You can use a mask to tell the CPU exactly which elements in the vector are non-zero, preventing the CPU from wasting cycles on empty data.

## RISC-V RVV
RVV uses a "Vector-Indexed" approach. It is often considered more flexible for sparse data because it supports different "widths" for the indices and the data more naturally.

### Best Instructions:
* **VLUXEI32.V / VLOXEI32.V**: These are "Vector Load Unordered/Ordered Indexed" instructions.
* **VRECOMPRESS.VM**: Similar to Intel's compress, it helps pack active elements.
* **LMUL (Register Grouping)**: A major advantage for SpMM in RVV is the ability to group registers (LMUL > 1). If your sparse indices are 16-bit but your data is 64-bit, you can group registers to ensure the "index" register has enough slots to match the "data" register.

**The "Secret Sauce"**: `vsetvli`. In sparse loops where the number of non-zero elements per row varies, `vsetvli` dynamically adjusts the hardware's "Vector Length" to match the actual work remaining, eliminating the need for complex "tail-handling" code.

## Godbolt Comparison: Sparse Vector Fetch
This example shows the "Gather" operation: fetching values from a dense vector `x` using indices from a sparse matrix.

### AVX10 (C++ Intrinsics)
```cpp
#include <immintrin.h>
// Fetch 16 floats from 'dense_x' using 'indices'
__m512 fetch_sparse_avx10(float* dense_x, int* indices) {
    __m512i v_indices = _mm512_loadu_si512(indices);
    // Gather: Scale of 4 (size of float)
    return _mm512_i32gather_ps(v_indices, dense_x, 4);
}
```

### RISC-V RVV (C Intrinsics)
```cpp
#include <riscv_vector.h>
// Fetch 'vl' floats from 'dense_x' using 'indices'
vfloat32m1_t fetch_sparse_rvv(float* dense_x, uint32_t* indices, size_t vl) {
    vuint32m1_t v_indices = __riscv_vle32_v_u32m1(indices, vl);
    // Indexed load (Gather)
    return __riscv_vluxei32_v_f32m1(dense_x, v_indices, vl);
}
```

## The OCP-MX+ Solution: Bit-Serial Sparse MAC

While AVX10 and RVV focus on the high-bandwidth "Gather" phase, the **OCP-MX+ (Tiny-Serial)** engine optimized for **SERV** handles the high-efficiency "MAC" (consumption) phase. In ultra-constrained designs, we replace wide SIMD units with a bit-serial pipe that consumes gathered data through the custom **OCP-MX-V** ISA.

### From Gather to Stream
In the OCP-MX+ architecture, the irregular access is handled by the SERV core (software-driven gather), while the arithmetic is offloaded to the bit-serial engine. The `MX.MAC` instruction acts as the bridge:

1.  **Software Gather**: The SERV core executes standard load instructions (using sparse indices) to fetch elements into registers.
2.  **Packing**: Elements are packed into 32-bit registers (4x 8-bit elements).
3.  **Consumption**: The `MX.MAC` instruction sends these 32-bit packed registers to the OCP-MX+ engine.
4.  **Bit-Serial Execution**: The engine processes the 4 MACs bit-serially over 32 cycles, perfectly overlapping with the SERV core's next instruction fetch/decode window.

### OCP-MX-V Sparse-MAC Loop
This example demonstrates a sparse dot product where one operand is fetched via indirect indexing and then streamed to the OCP-MX+ hardware.

```c
#include <stdint.h>

// Assembly Macros for OCP-MX-V (Opcode 0x0b)
#define MX_SETFMT(fmt) asm volatile (".insn r 0x0b, 0, 0, x0, %0, x0" :: "r"(fmt))
#define MX_MAC(va, vb)  asm volatile (".insn r 0x0b, 2, 0, x0, %0, %1" :: "r"(va), "r"(vb))

/**
 * Perform a Sparse Dot Product: result += sum(sparse_a[i] * dense_b[indices[i]])
 * - sparse_a: Packed 8-bit values (4 per uint32_t)
 * - dense_b: Dense array of 8-bit values
 * - indices: Array of indices (4 per uint32_t, each byte is an index)
 */
void sparse_mac_ocp_mx(uint32_t* sparse_a, uint8_t* dense_b, uint32_t* indices, int len) {
    for (int i = 0; i < len/4; i++) {
        uint32_t idx_quad = indices[i];

        // Software Gather: Fetch 4 elements from dense_b using the packed indices
        // On SERV, this is a sequence of 4 loads and shifts
        uint32_t gathered_b = (dense_b[(idx_quad >>  0) & 0xFF] <<  0) |
                              (dense_b[(idx_quad >>  8) & 0xFF] <<  8) |
                              (dense_b[(idx_quad >> 16) & 0xFF] << 16) |
                              (dense_b[(idx_quad >> 24) & 0xFF] << 24);

        // Send the packed sparse elements (A) and the gathered dense elements (B)
        // to the OCP-MX+ engine for processing.
        MX_MAC(sparse_a[i], gathered_b);
    }
}
```

## Summary of Strengths
* **AVX10** is generally faster for **Fixed-Block Sparsity** because of its high clock speeds and mature "Expand" instructions.
* **RVV** is superior for **Random/Unstructured Sparsity** because its vector-length agnosticism and register grouping make it much easier to write code.
* **OCP-MX+ (on SERV)** is the leader for **Area-Constrained Sparsity**. It provides AI acceleration in ~2000 gates by leveraging the bit-serial nature of the CPU to hide the latency of software-driven sparse gathering behind the bit-serial MAC execution.
