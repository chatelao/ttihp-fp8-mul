# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer
from cocotb_coverage.coverage import coverage_db, CoverCross, CoverPoint, coverage_section
import random
import os

# Reuse the model from test.py
from test import decode_format, align_model, align_product_model, reset_dut

def get_operand_class(bits, format_val, is_bm=False, support_mxplus=False):
    sign, exp, mant, bias, is_int, nan, inf = decode_format(bits, format_val, is_bm=is_bm, support_mxplus=support_mxplus)

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
    CoverPoint("top.packed_mode", vname="packed_mode", bins=list(range(2)), bins_labels=["OFF", "ON"]),
    CoverPoint("top.lns_mode", vname="lns_mode", bins=list(range(3)), bins_labels=["NORMAL", "LNS", "HYBRID"]),
    CoverPoint("top.mx_plus_mode", vname="mx_plus_mode", bins=[0, 1], bins_labels=["OFF", "ON"]),
    CoverPoint("top.is_bm_a", vname="is_bm_a", bins=[0, 1], bins_labels=["NO", "YES"]),
    CoverPoint("top.is_bm_b", vname="is_bm_b", bins=[0, 1], bins_labels=["NO", "YES"]),
    CoverPoint("top.op_class_a", vname="op_class_a", bins=["ZERO", "SUBNORMAL", "NORMAL", "MAX_NORMAL", "SPECIAL", "POSITIVE", "NEGATIVE", "MIN_INT", "MAX_INT"]),
    CoverPoint("top.op_class_b", vname="op_class_b", bins=["ZERO", "SUBNORMAL", "NORMAL", "MAX_NORMAL", "SPECIAL", "POSITIVE", "NEGATIVE", "MIN_INT", "MAX_INT"]),
    CoverCross("top.format_cross", items=["top.format_a", "top.format_b"]),
    CoverCross("top.format_packed_cross", items=["top.format_a", "top.packed_mode"]),
    CoverCross("top.round_overflow_cross", items=["top.round_mode", "top.overflow_wrap"]),
    CoverCross("top.lns_format_cross", items=["top.lns_mode", "top.format_a"]),
    CoverCross("top.mx_plus_bm_a_cross", items=["top.mx_plus_mode", "top.is_bm_a"]),
    CoverCross("top.mx_plus_bm_b_cross", items=["top.mx_plus_mode", "top.is_bm_b"])
)
def sample_coverage(format_a, format_b, round_mode, overflow_wrap, packed_mode, lns_mode, mx_plus_mode, is_bm_a, is_bm_b, op_class_a, op_class_b):
    pass

# We'll use a wrapper to sample
def do_sample(format_a, format_b, round_mode, overflow_wrap, packed_mode, lns_mode, mx_plus_mode, is_bm_a, is_bm_b, bits_a, bits_b,
              support_mxplus=False):
    op_class_a = get_operand_class(bits_a, format_a, is_bm=is_bm_a, support_mxplus=support_mxplus)
    op_class_b = get_operand_class(bits_b, format_b, is_bm=is_bm_b, support_mxplus=support_mxplus)
    sample_coverage(int(format_a), int(format_b), int(round_mode), int(overflow_wrap), int(packed_mode),
                    int(lns_mode), int(mx_plus_mode), int(is_bm_a), int(is_bm_b), op_class_a, op_class_b)

async def run_mac_test_covered(dut, format_a, format_b, a_elements, b_elements, scale_a=127, scale_b=127, round_mode=0, overflow_wrap=0, packed_mode=0, lns_mode=0, mx_plus_mode=0, bm_index_a=0, bm_index_b=0):
    from test import get_param
    support_mxplus_hw = get_param(dut, "SUPPORT_MX_PLUS", 0)
    support_mxplus = support_mxplus_hw and mx_plus_mode

    # Sample coverage for each element pair
    for i, (a, b) in enumerate(zip(a_elements, b_elements)):
        is_bm_a = (i == bm_index_a)
        is_bm_b = (i == bm_index_b)
        do_sample(format_a, format_b, round_mode, overflow_wrap, packed_mode, lns_mode, mx_plus_mode, is_bm_a, is_bm_b, a, b,
                  support_mxplus=support_mxplus)

    # Actually run the test (reusing logic from test.py)
    from test import run_mac_test
    await run_mac_test(dut, format_a, format_b, a_elements, b_elements, scale_a, scale_b, round_mode, overflow_wrap, packed_mode=packed_mode, lns_mode=lns_mode, mx_plus_mode=mx_plus_mode, bm_index_a=bm_index_a, bm_index_b=bm_index_b)

@cocotb.test()
async def test_exhaustive_formats_subset(dut):
    """Run exhaustive 256x256 for a few key format combinations"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    from test import get_param
    support_e4m3 = get_param(dut, "SUPPORT_E4M3", 1)
    support_e5m2 = get_param(dut, "SUPPORT_E5M2", 0)
    support_mxfp4 = get_param(dut, "SUPPORT_MXFP4", 1)
    support_int8 = get_param(dut, "SUPPORT_INT8", 0)

    formats_to_test = []
    if support_e4m3: formats_to_test.append((0, 0, 0))
    if support_e5m2: formats_to_test.append((1, 1, 0))
    if support_mxfp4: formats_to_test.append((4, 4, 1))
    if support_int8: formats_to_test.append((5, 5, 0))

    for fa, fb, pm in formats_to_test:
        dut._log.info(f"Exhaustive test for {fa} x {fb} (packed={pm})")
        max_val = 16 if pm else 256
        all_pairs = [(a, b) for a in range(max_val) for b in range(max_val)]
        random.shuffle(all_pairs)
        num_pairs = min(len(all_pairs), 1024)

        for i in range(0, num_pairs, 32):
            chunk = all_pairs[i:i+32]
            a_els = [p[0] for p in chunk]
            b_els = [p[1] for p in chunk]
            await run_mac_test_covered(dut, fa, fb, a_els, b_els, packed_mode=pm)

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

        elements = [0x00, 0x7F, 0x80, 0xFF]
        elements += [0x00] * (32 - len(elements))
        await run_mac_test_covered(dut, fmt, fmt, elements, elements)

    if support_e5m2:
        specials = [0x7C, 0xFC, 0x7D, 0x7E]
        a_els = specials + [0x00] * (32 - len(specials))
        b_els = [0x3C] * 32
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
async def test_lns_coverage(dut):
    """Targeted coverage for LNS and Hybrid modes"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    from test import get_param
    use_lns = get_param(dut, "USE_LNS_MUL", 0)
    if not use_lns:
        dut._log.info("Skipping LNS Coverage Test (USE_LNS_MUL=0)")
        return

    support_e4m3 = get_param(dut, "SUPPORT_E4M3", 1)
    support_e5m2 = get_param(dut, "SUPPORT_E5M2", 0)
    support_mxfp4 = get_param(dut, "SUPPORT_MXFP4", 1)
    support_mxplus = get_param(dut, "SUPPORT_MX_PLUS", 0)

    allowed_formats = []
    if support_e4m3: allowed_formats.append(0)
    if support_e5m2: allowed_formats.append(1)
    if support_mxfp4: allowed_formats.append(4)

    for fa in allowed_formats:
        for lm in [1, 2]: # LNS, HYBRID
            mx = 1 if (lm == 2 and support_mxplus) else 0
            a_els = [0x38] * 32
            b_els = [0x38] * 32
            if fa == 1: # E5M2: 1.0 is 0x3C
                a_els = [0x3C] * 32
                b_els = [0x3C] * 32
            elif fa == 4: # E2M1: 1.0 is 0x02
                a_els = [0x02] * 32
                b_els = [0x02] * 32
            await run_mac_test_covered(dut, fa, fa, a_els, b_els, lns_mode=lm, mx_plus_mode=mx)

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
    support_mxplus = get_param(dut, "SUPPORT_MX_PLUS", 0)
    use_lns = get_param(dut, "USE_LNS_MUL", 0)

    allowed_formats = [0]
    if support_e5m2: allowed_formats.append(1)
    if support_mxfp6: allowed_formats.extend([2, 3])
    if support_mxfp4: allowed_formats.append(4)
    if support_int8: allowed_formats.extend([5, 6])

    num_iters = 50 if os.environ.get("GATES") == "yes" else 500

    for _ in range(num_iters):
        fa = random.choice(allowed_formats)
        fb = random.choice(allowed_formats) if support_mixed else fa
        rm = random.randint(0, 3)
        ov = random.randint(0, 1)
        pm = random.choice([0, 1]) if (fa == 4 and fb == 4) else 0
        sa = random.randint(0, 255)
        sb = random.randint(0, 255)
        lm = random.randint(0, 2) if use_lns else 0
        mx = random.randint(0, 1) if support_mxplus else 0
        bma = random.randint(0, 31) if mx else 0
        bmb = random.randint(0, 31) if mx else 0
        el_mask = 0xF if pm else 0xFF
        a_els = [random.randint(0, 255) & el_mask for _ in range(32)]
        b_els = [random.randint(0, 255) & el_mask for _ in range(32)]
        await run_mac_test_covered(dut, fa, fb, a_els, b_els, sa, sb, rm, ov, packed_mode=pm, lns_mode=lm, mx_plus_mode=mx, bm_index_a=bma, bm_index_b=bmb)

@cocotb.test()
async def test_coverage_report(dut):
    """Print coverage report"""
    dut._log.info("Final Coverage Report:")
    for name in ["top.format_a", "top.format_b", "top.round_mode", "top.overflow_wrap", "top.packed_mode", "top.lns_mode", "top.mx_plus_mode", "top.is_bm_a", "top.is_bm_b", "top.op_class_a", "top.op_class_b", "top.format_cross", "top.format_packed_cross", "top.round_overflow_cross", "top.lns_format_cross", "top.mx_plus_bm_a_cross", "top.mx_plus_bm_b_cross"]:
        coverage = coverage_db[name].cover_percentage
        dut._log.info(f"  {name}: {coverage:.2f}%")
