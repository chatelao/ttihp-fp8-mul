# Concept: NaN and Infinity Propagation (Element-wise Detection)

This document expands on recommendation **7.2.2.1** from the project review, detailing the logic for detecting special values (NaN and Infinity) at the operand level for various OCP MX formats.

## 1. Overview
Numerical robustness in deep learning requires consistent handling of non-finite values. While the OCP MX specification primarily uses saturation for narrow formats (FP4, FP6), the 8-bit formats (E4M3, E5M2) include reserved encodings for NaN and Infinity that must be detected before arithmetic operations.

## 2. Special Value Encodings

### 2.1. E5M2 (IEEE-754 Style)
The E5M2 format follows standard IEEE-754 conventions for special values:
- **Infinity**: Exponent is all ones (`5'b11111`), and mantissa is zero (`2'b00`).
- **NaN (Not-a-Number)**: Exponent is all ones (`5'b11111`), and mantissa is non-zero (`2'b01`, `2'b10`, or `2'b11`).

### 2.2. E4M3 (OCP / FN8 Style)
The E4M3 format uses a single reserved encoding for NaN:
- **NaN**: Exponent is all ones (`4'b1111`), and mantissa is all ones (`3'b111`). Bit pattern: `S.1111.111`.
- **Infinities**: E4M3 does not have a dedicated infinity encoding; values that would overflow are typically saturated to the maximum normal value ($448$).

### 2.3. Shared Scale (E8M0)
- **NaN Scale**: A shared scale of `0xFF` (all ones) indicates that the entire block is NaN.

## 3. Implementation Logic: `decode_operand`

The `decode_operand` task in `src/fp8_mul.v` should be extended with two output flags: `nan_out` and `inf_out`.

### 3.1. Proposed Pseudo-code (Verilog)

```verilog
task automatic decode_operand(
    input [7:0] data,
    input [2:0] fmt,
    output reg nan_out,
    output reg inf_out,
    // ... existing outputs ...
);
    begin
        nan_out = 1'b0;
        inf_out = 1'b0;

        case (fmt)
            FMT_E4M3: begin
                // OCP E4M3 NaN is S.1111.111
                if (data[6:0] == 7'b1111111) nan_out = 1'b1;
                // ...
            end
            FMT_E5M2: begin
                if (data[6:2] == 5'b11111) begin
                    if (data[1:0] == 2'b00) inf_out = 1'b1;
                    else                   nan_out = 1'b1;
                end
                // ...
            end
            // ... FP4/FP6 do not have special values ...
        endcase
    end
endtask
```

## 4. Arithmetic Propagation Rules (Step 7.2.2.2)

Once detected, these flags must propagate through the multiplier:
- **NaN Propagation**: If either operand is NaN, the product is NaN.
- **Infinity Multiplication**:
    - `Inf * Normal` = `Inf`
    - `Inf * Inf` = `Inf`
    - `Inf * Zero` = `NaN` (Standard IEEE-754 rule)
- **Signage**: The sign of an Infinity result follows standard XOR rules ($S_A \oplus S_B$). NaNs are typically unsigned or "quiet" in these datapaths.

## 5. Next Steps
The subsequent steps in the roadmap (7.2.2.2 through 7.2.2.6) will define how these element-wise flags are combined into "sticky" block-level status bits in the accumulator and how they interact with the Shared Scale NaN rule.
