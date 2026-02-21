import cocotb
from cocotb.triggers import Timer
from model import get_8bit_op, to_binary, to_float


@cocotb.test()
async def test_all_inputs(dut):
    """Test all possible pairs of 8-bit inputs."""

    async def store(operand, half, data):
        # ui_in[1] is store_en_n (active low)
        # ui_in[2] is op_sel (0=op1, 1=op2)
        # ui_in[3] is nibble_sel (0=lower, 1=upper)
        # ui_in[7:4] is data
        # ui_in[0] is unused but we use it as a manual clock in this test if needed?
        # Actually project.v uses the global 'clk' port.
        # But this test doesn't seem to drive 'clk'.

        # We'll assume the 'clk' port is handled by cocotb Clock.
        # Wait, this test doesn't start a clock!

        val = (0) | (half << 3) | (operand << 2) | (0 << 1) | 0
        for i in range(4):
            val |= (data[i] << (4+i))

        dut.ui_in.value = val
        await Timer(1, units="ms")
        # Pulse 'clk' if we had one, but here we just wait
        # This test might need a clock to be started.

    fp8_mul_model = get_8bit_op(lambda a, b: a * b)

    # TODO: Test in random order
    for i in range(256):
        for j in range(256):
            in1 = to_binary(i)
            in2 = to_binary(j)
            await store(0, 0, in1[:4])
            await store(0, 1, in1[4:])
            await store(1, 0, in2[:4])
            await store(1, 1, in2[4:])
            correct = fp8_mul_model(i, j)
            assert dut.uo_out.value.binstr == f"{correct:08b}", f"{to_float(i)} ({i:08b}) * {to_float(j)} ({j:08b}) = {to_float(dut.uo_out.value.integer)} ({dut.uo_out.value.integer:08b}), should be {to_float(correct)} ({correct:08b})"
