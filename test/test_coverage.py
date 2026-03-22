# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer
from cocotb_coverage.coverage import coverage_db, CoverCross, CoverPoint, coverage_section
import random

# Reuse the model from test.py
from test import decode_format, align_model, align_product_model, reset_dut

def get_operand_class(bits, format_val,
                      support_e4m3=True, support_e5m2=True, support_mxfp6=True, support_mxfp4=True):
    sign, exp, mant, bias, is_int, nan, inf = decode_format(bits, format_val,
                                                          support_e4m3=support_e4m3, support_e5m2=support_e5m2,
                                                          support_mxfp6=support_mxfp6, support_mxfp4=support_mxfp4)

    if is_int:
        val = bits if bits < 128 else bits - 256
        if format_val == 6 and val == -128: val = -127 # INT8_SYM

        if val == 0: return "ZERO"
        if val == -128: return "MIN_INT"
        if val == 127: return "MAX_INT"
        if val < 0: return "NEGATIVE"
        return "POSITIVE"
    else:
        # FP formats
        if format_val == 0: # E4M3
            max_exp = 15
        elif format_val == 1: # E5M2
            max_exp = 31
        elif format_val == 2: # E3M2
            max_exp = 7
        elif format_val == 3: # E2M3
            max_exp = 3
        elif format_val == 4: # E2M1
            max_exp = 3
        else:
            max_exp = 15

        if exp == 0:
            return "ZERO" if mant == 0 else "SUBNORMAL"
        if exp == max_exp:
            if format_val == 1: # E5M2 has Inf/NaN
                return "SPECIAL"
            return "MAX_NORMAL"
        return "NORMAL"

# Coverage Definitions
@coverage_section(
    CoverPoint("top.format_a", vname="format_a", bins=list(range(7)), bins_labels=["E4M3", "E5M2", "E3M2", "E2M3", "E2M1", "INT8", "INT8_SYM"]),
    CoverPoint("top.format_b", vname="format_b", bins=list(range(7)), bins_labels=["E4M3", "E5M2", "E3M2", "E2M3", "E2M1", "INT8", "INT8_SYM"]),
    CoverPoint("top.round_mode", vname="round_mode", bins=list(range(4)), bins_labels=["TRN", "CEL", "FLR", "RNE"]),
    CoverPoint("top.overflow_wrap", vname="overflow_wrap", bins=list(range(2)), bins_labels=["SAT", "WRAP"]),
    CoverPoint("top.op_class_a", vname="op_class_a", bins=["ZERO", "SUBNORMAL", "NORMAL", "MAX_NORMAL", "SPECIAL", "POSITIVE", "NEGATIVE", "MIN_INT", "MAX_INT"]),
    CoverPoint("top.op_class_b", vname="op_class_b", bins=["ZERO", "SUBNORMAL", "NORMAL", "MAX_NORMAL", "SPECIAL", "POSITIVE", "NEGATIVE", "MIN_INT", "MAX_INT"]),
    CoverPoint("top.lns_mode", vname="lns_mode", bins=[0, 1, 2], bins_labels=["Normal", "LNS", "Hybrid"]),
    CoverPoint("top.is_bm_a", vname="is_bm_a", bins=[0, 1]),
    CoverPoint("top.is_bm_b", vname="is_bm_b", bins=[0, 1]),
    CoverCross("top.format_cross", items=["top.format_a", "top.format_b"]),
    CoverCross("top.round_overflow_cross", items=["top.round_mode", "top.overflow_wrap"]),
    CoverCross("top.lns_format_cross", items=["top.lns_mode", "top.format_a"])
)
def sample_coverage(format_a, format_b, round_mode, overflow_wrap, op_class_a, op_class_b, lns_mode, is_bm_a, is_bm_b):
    pass

# We'll use a wrapper to sample
def do_sample(format_a, format_b, round_mode, overflow_wrap, bits_a, bits_b,
              support_e4m3=True, support_e5m2=True, support_mxfp6=True, support_mxfp4=True,
              lns_mode=0, is_bm_a=0, is_bm_b=0):
    op_class_a = get_operand_class(bits_a, format_a, support_e4m3, support_e5m2, support_mxfp6, support_mxfp4)
    op_class_b = get_operand_class(bits_b, format_b, support_e4m3, support_e5m2, support_mxfp6, support_mxfp4)
    sample_coverage(format_a, format_b, round_mode, overflow_wrap, op_class_a, op_class_b, lns_mode, is_bm_a, is_bm_b)

async def run_mac_test_covered(dut, format_a, format_b, a_elements, b_elements, scale_a=127, scale_b=127, round_mode=0, overflow_wrap=0, bm_index_a=0, bm_index_b=0, nbm_offset_a=0, nbm_offset_b=0, mx_plus_mode=0, lns_mode=0):
    from test import get_param
    support_e4m3 = get_param(dut, "SUPPORT_E4M3", 1)
    support_e5m2 = get_param(dut, "SUPPORT_E5M2", 0)
    support_mxfp6 = get_param(dut, "SUPPORT_MXFP6", 0)
    support_mxfp4 = get_param(dut, "SUPPORT_MXFP4", 1)

    # Sample coverage for each element pair
    for i, (a, b) in enumerate(zip(a_elements, b_elements)):
        is_bm_a = 1 if (i == bm_index_a and mx_plus_mode) else 0
        is_bm_b = 1 if (i == bm_index_b and mx_plus_mode) else 0
        do_sample(format_a, format_b, round_mode, overflow_wrap, a, b,
                  support_e4m3, support_e5m2, support_mxfp6, support_mxfp4,
                  lns_mode, is_bm_a, is_bm_b)

    # Actually run the test (reusing logic from test.py)
    from test import run_mac_test
    await run_mac_test(dut, format_a, format_b, a_elements, b_elements, scale_a, scale_b, round_mode, overflow_wrap,
                       bm_index_a=bm_index_a, bm_index_b=bm_index_b, nbm_offset_a=nbm_offset_a, nbm_offset_b=nbm_offset_b,
                       mx_plus_mode=mx_plus_mode, lns_mode=lns_mode)

@cocotb.test()
async def test_exhaustive_formats_subset(dut):
    """Run exhaustive 256x256 for a few key format combinations"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    from test import get_param
    support_e4m3 = get_param(dut, "SUPPORT_E4M3", 1)
    support_e5m2 = get_param(dut, "SUPPORT_E5M2", 0)
    support_int8 = get_param(dut, "SUPPORT_INT8", 0)

    formats_to_test = []
    if support_e4m3: formats_to_test.append((0, 0))
    if support_e5m2: formats_to_test.append((1, 1))
    if support_int8: formats_to_test.append((5, 5))

    for fa, fb in formats_to_test:
        dut._log.info(f"Exhaustive test for {fa} x {fb}")
        # To avoid taking forever in a single MAC run (32 elements),
        # we'll do 256*256 / 32 = 2048 MAC runs.
        # But that's still a lot. Maybe just 1000 random pairs or a smaller exhaustive set.
        # Let's do 256x256 in chunks.

        all_pairs = [(a, b) for a in range(256) for b in range(256)]
        random.shuffle(all_pairs)

        for i in range(0, 1024, 32): # Just test 1024 pairs per format to keep it reasonable
            chunk = all_pairs[i:i+32]
            a_els = [p[0] for p in chunk]
            b_els = [p[1] for p in chunk]
            await run_mac_test_covered(dut, fa, fb, a_els, b_els)

@cocotb.test()
async def test_edge_cases(dut):
    """Targeted edge cases for all formats"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    from test import get_param
    support_e5m2 = get_param(dut, "SUPPORT_E5M2", 0)
    support_mxfp6 = get_param(dut, "SUPPORT_MXFP6", 0)
    support_mxfp4 = get_param(dut, "SUPPORT_MXFP4", 1)
    support_int8 = get_param(dut, "SUPPORT_INT8", 0)

    for fmt in range(7):
        if fmt == 1 and not support_e5m2: continue
        if fmt in [2, 3] and not support_mxfp6: continue
        if fmt == 4 and not support_mxfp4: continue
        if fmt in [5, 6] and not support_int8: continue

        # Zero, Min, Max, Special
        elements = [0x00, 0x7F, 0x80, 0xFF]
        # Pad to 32
        elements += [0x00] * (32 - len(elements))
        await run_mac_test_covered(dut, fmt, fmt, elements, elements)

    # E5M2 Infinities and NaNs
    if support_e5m2:
        # E5M2: exp is bits [6:2]. exp=31 is special.
        # 0x7C is +Inf (0 11111 00)
        # 0xFC is -Inf (1 11111 00)
        # 0x7D is NaN
        specials = [0x7C, 0xFC, 0x7D, 0x7E]
        a_els = specials + [0x00] * (32 - len(specials))
        b_els = [0x3C] * 32 # 1.0 in E5M2
        await run_mac_test_covered(dut, 1, 1, a_els, b_els)

@cocotb.test()
async def test_shared_scale_coverage(dut):
    """Test various shared scale combinations"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    scales = [0, 127, 128, 255]
    for sa in scales:
        for sb in scales:
            a_els = [0x38] * 32
            b_els = [0x38] * 32
            await run_mac_test_covered(dut, 0, 0, a_els, b_els, scale_a=sa, scale_b=sb)

@cocotb.test()
async def test_randomized_coverage(dut):
    """Run many randomized tests to fill coverage"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    from test import get_param
    support_e5m2 = get_param(dut, "SUPPORT_E5M2", 0)
    support_mxfp6 = get_param(dut, "SUPPORT_MXFP6", 0)
    support_mxfp4 = get_param(dut, "SUPPORT_MXFP4", 1)
    support_int8 = get_param(dut, "SUPPORT_INT8", 0)
    support_mixed = get_param(dut, "SUPPORT_MIXED_PRECISION", 0)

    allowed_formats = [0]
    if support_e5m2: allowed_formats.append(1)
    if support_mxfp6: allowed_formats.extend([2, 3])
    if support_mxfp4: allowed_formats.append(4)
    if support_int8: allowed_formats.extend([5, 6])

    for _ in range(500):
        fa = random.choice(allowed_formats)
        fb = random.choice(allowed_formats) if support_mixed else fa
        rm = random.randint(0, 3)
        ov = random.randint(0, 1)
        sa = random.randint(0, 255)
        sb = random.randint(0, 255)
        a_els = [random.randint(0, 255) for _ in range(32)]
        b_els = [random.randint(0, 255) for _ in range(32)]

        lns = random.randint(0, 2)
        mxp = random.randint(0, 1)
        bm_a = random.randint(0, 31)
        bm_b = random.randint(0, 31)
        off_a = random.randint(0, 7)
        off_b = random.randint(0, 7)

        await run_mac_test_covered(dut, fa, fb, a_els, b_els, sa, sb, rm, ov,
                                   bm_index_a=bm_a, bm_index_b=bm_b,
                                   nbm_offset_a=off_a, nbm_offset_b=off_b,
                                   mx_plus_mode=mxp, lns_mode=lns)

@cocotb.test()
async def test_lns_dedicated_coverage(dut):
    """Specifically target LNS and Hybrid mode transitions and corner cases"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    from test import get_param
    use_lns = get_param(dut, "USE_LNS_MUL", 0)
    if not use_lns:
        dut._log.info("Skipping Dedicated LNS Coverage (USE_LNS_MUL=0)")
        return

    support_mixed = get_param(dut, "SUPPORT_MIXED_PRECISION", 0)
    support_e5m2 = get_param(dut, "SUPPORT_E5M2", 0)

    # Test all 3 LNS modes across supported formats
    fmts = [0]
    if support_e5m2: fmts.append(1)

    for lns in [0, 1, 2]: # Normal, LNS, Hybrid
        for fa in fmts:
            fb = random.choice(fmts) if support_mixed else fa
            # 1. Standard Case
            a_els = [random.randint(0, 255) for _ in range(32)]
            b_els = [random.randint(0, 255) for _ in range(32)]
            await run_mac_test_covered(dut, fa, fb, a_els, b_els, lns_mode=lns, mx_plus_mode=(1 if lns==2 else 0))

            # 2. Hybrid Mode: Ensure BM is exercised at multiple positions
            if lns == 2:
                for bm_pos in [0, 15, 31]:
                    await run_mac_test_covered(dut, fa, fb, a_els, b_els, lns_mode=2, mx_plus_mode=1, bm_index_a=bm_pos, bm_index_b=bm_pos)

@cocotb.test()
async def test_coverage_report(dut):
    """Print coverage report"""
    dut._log.info("Final Coverage Report:")
    # Log individual coverage points
    for name in ["top.format_a", "top.format_b", "top.round_mode", "top.overflow_wrap", "top.op_class_a", "top.op_class_b", "top.format_cross", "top.lns_mode", "top.is_bm_a", "top.is_bm_b", "top.lns_format_cross"]:
        if name in coverage_db:
            coverage = coverage_db[name].cover_percentage
            dut._log.info(f"  {name}: {coverage:.2f}%")
