# SERV README
Fetched from https://github.com/olofk/serv

SERV is a bit-serial RISC-V core.
Area: 2.1kGE (CMOS).

## Key concepts
- Any N-bit operation is decomposed into N 1-bit operations over N clock cycles.
- Registers as Shift Registers (or memory-based RF).
- 1-Bit Datapath.

## Extension Interface
SERV can be extended using an extension interface. custom accelerators are called when specific instructions are encountered.
MDU (Multiplication/Division Unit) is an example.
