# Analysis of LNS-based Approximate Multiplier using Modified Operand Decomposition

Based on the research paper *"Design of LNS based Approximate Multiplier using Mitchell’s Algorithm and Modified Operand Decomposition Technique"* (IJERT, 2019), the following metrics regarding area and precision were identified.

## 1. Precision Gained

The Modified Operand Decomposition (MOD) technique significantly reduces the Average Error Percentage (AEP) compared to the standard Mitchell's Algorithm (MA). The decomposition reduces the number of '1' bits in the operands, which is the primary source of error in Mitchell's approximation.

### Average Error Percentage (AEP) Comparison

| Multiplicand Width | Standard Mitchell Algorithm | Modified Operand Decomposition | Error Reduction (Absolute) |
|:-------------------|:---------------------------:|:------------------------------:|:--------------------------:|
| 4-bit              | N/A                         | 1.627%                         | N/A                        |
| 8-bit              | 3.76%                       | 1.65%                          | **2.11%**                  |
| 16-bit             | 3.91%                       | 2.10%                          | **1.81%**                  |

*Note: The worst-case error for standard MA is cited as 11.12%, while the MOD technique brings the average error down to ~1.6% for 8-bit operands.*

## 2. Additional Area Needed

While the paper claims overall area improvements compared to traditional exact multipliers, the implementation of the Modified Operand Decomposition requires several additional hardware components relative to a base Mitchell's Algorithm core.

### Inferred Hardware Overhead
To implement the product $X \times Y = (X_1 \times A) + (X_1 \times B)$ where $X_1 = \max(X, Y)$, $A = X_1 \text{ AND } Y_1$, and $B = \text{NOT } X_1 \text{ AND } Y_1$, the following components are added:

1.  **Comparator logic:** An $n$-bit comparator is required to identify the larger operand ($X_1$).
2.  **Decomposition Logic:** A set of AND and NOT gates to produce the decomposed operands $A$ and $B$.
3.  **Arithmetic Path Duplication:** The core Mitchell logic (Logarithmic conversion, Addition, and Antilogarithmic conversion) must process two paths ($X_1 \times A$ and $X_1 \times B$) instead of one.
4.  **Final Accumulation:** A $2n$-bit Ripple Carry Adder (RCA) is required to sum the two partial approximate products.

### Estimated Area Scaling
The area is approximately **double** that of a single Mitchell core, plus the fixed overhead of the comparator and the final adder. However, this total area remains significantly smaller than a standard Booth or Wallace-tree multiplier of the same bit-width.
