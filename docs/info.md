<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

The project implements a simple 8-bit combinational adder. It takes two 8-bit inputs: `ui_in` (Operand A) and `uio_in` (Operand B, configured as input). It outputs the 8-bit sum on `uo_out`.

## How to test

To test the adder:
1. Apply the first 8-bit number to the dedicated input pins `ui_in[7:0]`.
2. Apply the second 8-bit number to the bidirectional pins `uio_in[7:0]`.
3. Read the result from the dedicated output pins `uo_out[7:0]`.
4. Verify that `uo_out` equals the sum of `ui_in` and `uio_in`.

## External hardware

No external hardware is required.
