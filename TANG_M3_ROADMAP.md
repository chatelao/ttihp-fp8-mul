# Tang Nano 4K Cortex-M3 Testbench Roadmap

1. [x] **Hardware Setup (Gowin EDA)**
    - [x] Instantiate `Gowin_EMPU_M3` IP core in the project (Implemented in `src_gowin/tt_gowin_top_m3.v`).
    - [x] Configure IP: Enable AHB/APB buses, UART0, and at least 20 bits for GPIO0 (Configured in Verilog mapping).
    - [x] Allocate 16KB+ internal SRAM for instruction/data memory (Defined in `src_m3/link.ld`).
    - [x] Connect fabric signals: Map M3 GPIO[7:0] to `ui_in[7:0]`, GPIO[15:8] to `uio_in[7:0]`, GPIO[16] to `clk`, GPIO[17] to `rst_n`, GPIO[18] to `ena`, and MAC `uo_out[7:0]` to M3 GPIO[26:19].
2. [x] **M3 Software Implementation**
    - [x] Define base addresses: UART0 (0x40000000) and GPIO0 (0x40010000) (Implemented in `src_m3/main.c`).
    - [x] Implement low-level UART drivers (`uart_putc`, `uart_puts`, `uart_getc`).
    - [x] Implement `clock_tick()` with software delay loops.
    - [x] Implement `run_mac_test()` to drive the 41-cycle MAC protocol (Enhanced March 2025).
    - [x] Develop interactive CLI in `main()` with support for E4M3, E5M2, Packed, and Short Protocol tests.
3. [x] **Toolchain and Compilation**
    - [x] Set up Arm GNU Toolchain (`arm-none-eabi-gcc`) (Installed in environment).
    - [x] Obtain/configure linker script (`link.ld`) for the GW1NSR-4C memory map (Implemented in `src_m3/link.ld`).
    - [x] Compile `main.c` and use `objcopy` to generate raw binary (`testbench.bin`) (Automated with `src_m3/Makefile`).
4. [ ] **Integration and Execution**
    - [ ] Point Gowin EDA EMPU IP "Instruction Memory" path to `testbench.bin`.
    - [ ] Execute Synthesis and Place & Route (PNR) using `src_gowin/tangnano4k_m3.cst`.
    - [ ] Flash the resulting bitstream (`.fs`) to the Tang Nano 4K.
    - [ ] Connect serial terminal at 115200 baud to pins 18/19.
5. [x] **Troubleshooting and Refinement**
    - [x] Validate UART0 physical pin mapping (Pins 18/19 assigned in `tangnano4k_m3.cst`).
    - [x] Verify `clock_tick()` timing for reliable fabric sampling.
    - [x] Audit physical pin usage (30-44) to prevent conflicts (Completed March 2025).
