cases = [
    (101, "E4M3 Max Finite * 1.0", 0, 0, 127, 127, 0x7E, 0x38, 3670016),
    (102, "E4M3 Negative Max Finite * 1.0", 0, 0, 127, 127, 0xFE, 0x38, -3670016),
    (103, "E4M3 Subnormal (0x01) * Max Finite (0x7E)", 0, 0, 127, 127, 0x01, 0x7E, 7168),
    (104, "E4M3 Negative Subnormal (0x81) * Max Finite (0x7E)", 0, 0, 127, 127, 0x81, 0x7E, -7168),
    (105, "E4M3 Zero * Max Finite", 0, 0, 127, 127, 0x00, 0x7E, 0),
    (106, "E5M2 Max Finite * 1.0", 1, 1, 127, 127, 0x7B, 0x3C, 469762048),
    (107, "E5M2 Negative Max Finite * 1.0", 1, 1, 127, 127, 0xFB, 0x3C, -469762048),
    (108, "E5M2 Subnormal (0x01) * Max Finite (0x7B)", 1, 1, 127, 127, 0x01, 0x7B, 7168),
    (109, "E5M2 Negative Subnormal (0x81) * Max Finite (0x7B)", 1, 1, 127, 127, 0x81, 0x7B, -7168),
    (110, "E5M2 Infinity * 1.0", 1, 1, 127, 127, 0x7C, 0x3C, 2139095040),
    (111, "E5M2 Negative Infinity * 1.0", 1, 1, 127, 127, 0xFC, 0x3C, -8388608),
    (112, "E5M2 Zero * Infinity = NaN result", 1, 1, 127, 127, 0x00, 0x7C, 2143289344),
    (113, "E2M1 Max * 1.0", 4, 4, 127, 127, 0x07, 0x02, 49152),
    (114, "E2M1 Negative Max * 1.0", 4, 4, 127, 127, 0x0F, 0x02, -49152),
    (115, "E2M1 Negative Subnormal (0x09) * 1.0", 4, 4, 127, 127, 0x09, 0x02, -4096),
    (116, "E2M1 Negative Zero * 1.0", 4, 4, 127, 127, 0x08, 0x02, 0),
    (117, "Saturation Check: Max * Max with large scale", 0, 0, 140, 127, 0x7E, 0x7E, 2147483647),
    (118, "E4M3 Negative Zero * 1.0", 0, 0, 127, 127, 0x80, 0x38, 0),
    (119, "E5M2 Negative Zero * 1.0", 1, 1, 127, 127, 0x80, 0x3C, 0)
]

with open("test/TEST_MIN_MAX_ZERO.yaml", "w") as f:
    for tc, comment, fa, fb, sa, sb, a_val, b_val, exp in cases:
        f.write(f"- test_case: {tc}\n")
        f.write(f"  comment: \"{comment}\"\n")
        f.write(f"  inputs:\n")
        f.write(f"    format_a: {fa}\n")
        f.write(f"    format_b: {fb}\n")
        f.write(f"    scale_a: {sa}\n")
        f.write(f"    scale_b: {sb}\n")
        a_list = ", ".join([f"0x{a_val:02x}"] * 32)
        b_list = ", ".join([f"0x{b_val:02x}"] * 32)
        f.write(f"    a_elements: [{a_list}]\n")
        f.write(f"    b_elements: [{b_list}]\n")
        f.write(f"  expected_output: {exp}\n\n")
