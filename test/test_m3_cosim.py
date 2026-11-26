import os
import queue
import struct
import threading
import time

import cocotb
from cocotb.triggers import RisingEdge, Timer
from unicorn import Uc, UC_ARCH_ARM, UC_MODE_THUMB, UC_MODE_MCLASS
from unicorn import UC_HOOK_MEM_READ, UC_HOOK_MEM_WRITE, UcError
from unicorn.arm_const import UC_ARM_REG_SP, UC_ARM_REG_PC


FLASH_BASE = 0x00000000
FLASH_SIZE = 32 * 1024
SRAM_BASE  = 0x20000000
SRAM_SIZE  = 16 * 1024

UART0_BASE = 0x40004000
GPIO0_BASE = 0x40010000
APB2_BASE  = 0x40002400
AHB2_BASE  = 0xA0000000


def get_bfm(dut):
    """Return the Gowin_EMPU_Top BFM instance inside tt_gowin_top_m3."""
    top = dut.dut
    if hasattr(top, "gen_m3_ahb"):
        return top.gen_m3_ahb.m3_inst
    return top.gen_m3_standard.m3_inst


async def dma_slave_responder(dut, bfm, mu, stop_event):
    """
    Services AHB2 Slave DMA transfers (slave_h*) initiated by ahb2_mac_bridge
    directly against Unicorn's emulated Cortex-M3 SRAM (0x20000000..0x20003FFF).
    """
    pending_write = False
    pending_waddr = 0

    while not stop_event.is_set():
        await RisingEdge(dut.ext_clk)
        if stop_event.is_set():
            break

        # Complete data phase of a prior write
        if pending_write:
            wdata = int(bfm.slave_hwdata.value)
            if SRAM_BASE <= pending_waddr <= SRAM_BASE + SRAM_SIZE - 4:
                mu.mem_write(pending_waddr, struct.pack("<I", wdata))
            pending_write = False

        hsel = int(bfm.slave_hsel.value)
        htrans = int(bfm.slave_htrans.value)
        if hsel and (htrans & 0x2):
            addr = int(bfm.slave_haddr.value)
            hwrite = int(bfm.slave_hwrite.value)
            if hwrite:
                pending_write = True
                pending_waddr = addr
            else:
                if SRAM_BASE <= addr <= SRAM_BASE + SRAM_SIZE - 4:
                    raw = mu.mem_read(addr, 4)
                    rdata = struct.unpack("<I", raw)[0]
                else:
                    rdata = 0
                bfm.slave_hrdata.value = rdata


class M3CosimBridge:
    """
    Bridges ARM Cortex-M3 firmware executing in Unicorn Engine to tt_gowin_top_m3
    simulated in Icarus Verilog via cocotb.
    """

    def __init__(self, dut, bfm, bin_path):
        self.dut = dut
        self.bfm = bfm
        self.bin_path = bin_path

        self.req_q = queue.Queue()
        self.resp_q = queue.Queue()
        self.stop_event = threading.Event()

        # Virtual BL702 USB-UART buffers
        self.uart_tx_chars = []
        self.uart_rx_queue = queue.Queue()
        self.uart_lock = threading.Lock()

        # CMSDK GPIO0 shadowed state
        self.gpio_dataout = 0
        self.gpio_outen = 0

        # Initialize Unicorn Cortex-M3
        self.mu = Uc(UC_ARCH_ARM, UC_MODE_THUMB | UC_MODE_MCLASS)
        self.mu.mem_map(FLASH_BASE, FLASH_SIZE)
        self.mu.mem_map(SRAM_BASE, SRAM_SIZE)
        # Map peripheral MMIO regions
        self.mu.mem_map(0x40000000, 0x20000)
        self.mu.mem_map(0xA0000000, 0x10000)

        with open(bin_path, "rb") as f:
            fw = f.read()
        self.mu.mem_write(FLASH_BASE, fw)

        # Register MMIO hooks
        self.mu.hook_add(UC_HOOK_MEM_READ, self._hook_mem_read, begin=0x40000000, end=0x4001FFFF)
        self.mu.hook_add(UC_HOOK_MEM_WRITE, self._hook_mem_write, begin=0x40000000, end=0x4001FFFF)
        self.mu.hook_add(UC_HOOK_MEM_READ, self._hook_mem_read, begin=0xA0000000, end=0xA000FFFF)
        self.mu.hook_add(UC_HOOK_MEM_WRITE, self._hook_mem_write, begin=0xA0000000, end=0xA000FFFF)

    def _rpc(self, op, addr, size, value=0):
        if self.stop_event.is_set():
            return 0
        self.req_q.put((op, addr, size, value))
        return self.resp_q.get()

    def _hook_mem_read(self, uc, access, address, size, value, user_data):
        if self.stop_event.is_set():
            uc.emu_stop()
            return
        # Fast-path UART0 RX/STATE without stalling CPU unnecessarily
        if UART0_BASE <= address < UART0_BASE + 0x20:
            off = address - UART0_BASE
            if off == 0x04:  # UART0_STATE: bit1 = RX not empty, bit0 = TX full (0)
                if not self.uart_rx_queue.empty():
                    val = 0x02
                else:
                    self._rpc("TICK", address, size, 0)
                    val = 0x02 if not self.uart_rx_queue.empty() else 0x00
            elif off == 0x00:  # UART0_DATA RX
                try:
                    val = self.uart_rx_queue.get_nowait() & 0xFF
                except queue.Empty:
                    val = 0
            else:
                val = 0
        else:
            val = self._rpc("READ", address, size, 0)

        masked = val & ((1 << (8 * size)) - 1)
        uc.mem_write(address, masked.to_bytes(size, "little"))

    def _hook_mem_write(self, uc, access, address, size, value, user_data):
        if self.stop_event.is_set():
            uc.emu_stop()
            return
        if UART0_BASE <= address < UART0_BASE + 0x20:
            off = address - UART0_BASE
            if off == 0x00:  # UART0_DATA TX
                ch = chr(value & 0xFF)
                with self.uart_lock:
                    self.uart_tx_chars.append(ch)
            return
        self._rpc("WRITE", address, size, value)

    def send_serial(self, text):
        for ch in text:
            self.uart_rx_queue.put(ord(ch))

    def get_serial_output(self):
        with self.uart_lock:
            return "".join(self.uart_tx_chars)

    def start_cpu(self):
        sp, reset_vec = struct.unpack("<II", self.mu.mem_read(FLASH_BASE, 8))
        self.mu.reg_write(UC_ARM_REG_SP, sp)
        self.mu.reg_write(UC_ARM_REG_PC, reset_vec)

        def runner():
            try:
                self.mu.emu_start(reset_vec | 1, 0)
            except UcError:
                pass

        self.thread = threading.Thread(target=runner, daemon=True)
        self.thread.start()

    async def handle_mmio(self, op, addr, size, value):
        bfm = self.bfm
        if op == "TICK":
            await RisingEdge(self.dut.ext_clk)
            return 0

        # --- GPIO0 (0x40010000) ---
        if GPIO0_BASE <= addr < GPIO0_BASE + 0x40:
            off = addr - GPIO0_BASE
            if op == "WRITE":
                if off == 0x04:  # DATAOUT
                    self.gpio_dataout = value & 0xFFFF
                elif off == 0x10:  # OUTENSET
                    self.gpio_outen |= (value & 0xFFFF)
                elif off == 0x14:  # OUTENCLR
                    self.gpio_outen &= ~(value & 0xFFFF)
                bfm.gpioout.value = self.gpio_dataout & self.gpio_outen
                bfm.gpioouten.value = self.gpio_outen
                # Advance 2 clocks so edge-detector in tt_gowin_top_m3 pulses mac_ena for 1 cycle cleanly
                await RisingEdge(self.dut.ext_clk)
                await RisingEdge(self.dut.ext_clk)
                return 0
            else:  # READ
                await Timer(1, unit="ns")
                ext_in = int(bfm.gpioin.value)
                if off == 0x00:  # DATA
                    return (self.gpio_dataout & self.gpio_outen) | (ext_in & (~self.gpio_outen & 0xFFFF))
                elif off == 0x04:  # DATAOUT
                    return self.gpio_dataout
                elif off in (0x10, 0x14):
                    return self.gpio_outen
                return 0

        # --- APB2 Master Slot 1 (0x40002400) ---
        if APB2_BASE <= addr < APB2_BASE + 0x100:
            paddr = addr & 0xFF
            if op == "WRITE":
                bfm.master_psel1.value = 1
                bfm.master_penable.value = 0
                bfm.master_pwrite.value = 1
                bfm.master_paddr.value = paddr
                bfm.master_pwdata.value = value & 0xFFFFFFFF
                await RisingEdge(self.dut.ext_clk)
                bfm.master_penable.value = 1
                await RisingEdge(self.dut.ext_clk)
                bfm.master_psel1.value = 0
                bfm.master_penable.value = 0
                bfm.master_pwrite.value = 0
                await RisingEdge(self.dut.ext_clk)
                return 0
            else:
                bfm.master_psel1.value = 1
                bfm.master_penable.value = 0
                bfm.master_pwrite.value = 0
                bfm.master_paddr.value = paddr
                await RisingEdge(self.dut.ext_clk)
                bfm.master_penable.value = 1
                await Timer(1, unit="ns")
                rdata = int(bfm.master_prdata1.value)
                await RisingEdge(self.dut.ext_clk)
                bfm.master_psel1.value = 0
                bfm.master_penable.value = 0
                return rdata

        # --- AHB2 Master TARGEXP0 (0xA0000000) ---
        if AHB2_BASE <= addr < AHB2_BASE + 0x100:
            if op == "WRITE":
                bfm.master_hsel.value = 1
                bfm.master_htrans.value = 2  # NONSEQ
                bfm.master_hwrite.value = 1
                bfm.master_hsize.value = 2   # Word
                bfm.master_haddr.value = addr
                bfm.master_hreadymux.value = 1
                await RisingEdge(self.dut.ext_clk)
                bfm.master_hsel.value = 0
                bfm.master_htrans.value = 0
                bfm.master_hwrite.value = 0
                bfm.master_hwdata.value = value & 0xFFFFFFFF
                await RisingEdge(self.dut.ext_clk)
                await RisingEdge(self.dut.ext_clk)
                return 0
            else:
                bfm.master_hsel.value = 1
                bfm.master_htrans.value = 2  # NONSEQ
                bfm.master_hwrite.value = 0
                bfm.master_hsize.value = 2
                bfm.master_haddr.value = addr
                bfm.master_hreadymux.value = 1
                await RisingEdge(self.dut.ext_clk)
                bfm.master_hsel.value = 0
                bfm.master_htrans.value = 0
                await Timer(1, unit="ns")
                rdata = int(bfm.master_hrdata.value)
                await RisingEdge(self.dut.ext_clk)
                return rdata

        return 0

    def stop(self):
        self.stop_event.set()
        self.mu.emu_stop()
        # Unblock any pending RPC
        try:
            self.resp_q.put_nowait(0)
        except Exception:
            pass


async def wait_for_output(bridge, dut, substring, max_cycles=50000):
    for _ in range(max_cycles):
        # Drain any pending MMIO calls from Unicorn
        handled = False
        while True:
            try:
                op, addr, size, val = bridge.req_q.get_nowait()
            except queue.Empty:
                # Release GIL briefly so the Unicorn worker thread can execute up to its next MMIO
                time.sleep(0.00002)
                try:
                    op, addr, size, val = bridge.req_q.get_nowait()
                except queue.Empty:
                    break
            handled = True
            resp = await bridge.handle_mmio(op, addr, size, val)
            bridge.resp_q.put(resp)

        if substring in bridge.get_serial_output():
            return bridge.get_serial_output()

        if not handled:
            await RisingEdge(dut.ext_clk)

    pc = bridge.mu.reg_read(UC_ARM_REG_PC)
    raise AssertionError(
        f"Timeout (PC={hex(pc)}) waiting for {substring!r} in UART output:\n{bridge.get_serial_output()}"
    )


@cocotb.test()
async def test_m3_firmware_cosim(dut):
    """
    End-to-end Cortex-M3 (Unicorn) + FPGA RTL (Icarus Verilog) co-simulation
    over emulated BL702 serial UART0.
    """
    mode = os.environ.get("COSIM_MODE", "GPIO")
    bin_path = os.environ.get(
        "M3_FIRMWARE_BIN",
        os.path.join(os.path.dirname(__file__), "..", "src_m3", "testbench.bin"),
    )
    assert os.path.exists(bin_path), f"Missing compiled M3 firmware: {bin_path}"

    dut._log.info(f"Starting M3+FPGA co-simulation in mode={mode} using {bin_path}")

    # Release external reset
    dut.ext_rst_n.value = 0
    for _ in range(5):
        await RisingEdge(dut.ext_clk)
    dut.ext_rst_n.value = 1
    for _ in range(2):
        await RisingEdge(dut.ext_clk)

    bfm = get_bfm(dut)
    bridge = M3CosimBridge(dut, bfm, bin_path)

    dma_task = cocotb.start_soon(dma_slave_responder(dut, bfm, bridge.mu, bridge.stop_event))
    bridge.start_cpu()

    try:
        # 1. Wait for boot banner
        await wait_for_output(bridge, dut, "Commands:")

        # 2. Version check over virtual BL702 serial
        bridge.send_serial("v")
        await wait_for_output(bridge, dut, "Firmware Version: 1.3.0-M3-MXFP8")

        # 3. E4M3 1.0 x 1.0 x 32 -> 0x00002000 (32.0)
        bridge.send_serial("t")
        await wait_for_output(bridge, dut, "E4M3 Standard...\r\nResult: 0x00002000")

        # 4. Short Protocol reusing E4M3 scales -> 0x00002000 (32.0)
        bridge.send_serial("s")
        await wait_for_output(bridge, dut, "Short Protocol (Reuse Scales)...\r\nResult: 0x00002000")

        # 5. E5M2 1.0 x 1.0 x 32 -> 0x00002000 (32.0)
        bridge.send_serial("e")
        await wait_for_output(bridge, dut, "E5M2 Standard...\r\nResult: 0x00002000")

        # 6. INT8 (0x01 * 0x01 in Q1.6 * 32 -> 0x00000000 in Q23.8)
        bridge.send_serial("i")
        await wait_for_output(bridge, dut, "INT8 Standard...\r\nResult: 0x00000000")

        # 7. Packed FP4 Dual-Lane 1.0 x 1.0 x 32 -> 0x00002000 (32.0)
        bridge.send_serial("p")
        out = await wait_for_output(bridge, dut, "Packed FP4 (Dual Lane)...\r\nResult: 0x00002000")

        dut._log.info(f"PASS: M3+FPGA co-simulation ({mode}) passed all CLI tests!\n{out}")
    finally:
        bridge.stop()
        await Timer(10, unit="ns")
        dma_task.cancel()
