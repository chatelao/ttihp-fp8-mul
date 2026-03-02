# SERV Internals
Fetched from https://serv.readthedocs.io/en/latest/internals.html

## Modules
- serv_alu: Handles 1-bit ALU operations.
- serv_bufreg: Holds data between stages for two-stage operations. Parallel output for dbus address.
- serv_bufreg2: 32-bit buffer register. Used for shift amount, load/store data, and rs2 for extension interface.
- serv_ctrl: PC tracking and next PC calculation.
- serv_decode: Decodes instruction word into control signals.
- serv_state: FSM for core state and dynamic control signals.

## Instruction Life Cycle
1. Fetch: Request via ibus.
2. Decode: Save opcode, funct3, immediate. Request RF access.
3. Execute: 32 consecutive cycles (for 32-bit data).

## Two-Stage Operations
Operations like memory, shift, slt, and branch.
- Init Stage: Operands read, address calculated or shift amount stored.
- Execution: For memory, wait for dbus ack. For shifts, delay data or start.

## Extension Interface Integration
SERV treats extension instructions as two-stage operations.
RS1 and RS2 are provided in parallel.
Accelerator returns RD in parallel.
Internal to SERV, these are likely converted from/to the bit-serial stream if the RF is bit-serial, but the interface exposed is parallel.
Actually, the manual says: "the values in o_ext_rs1 and o_ext_rs2 are prepared to be sent to the accelerator".
Looking at `serv_bufreg2`, it holds rs2 for the extension interface and connects the "whole buffer" to the data bus or extension interface.
