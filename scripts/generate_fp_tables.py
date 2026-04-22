import os

def decode_e2m1(bits):
    sign_bit = (bits >> 3) & 1
    exp_field = (bits >> 1) & 0x3
    mant_field = (bits & 0x1)
    sign = "-" if sign_bit else "+"

    if exp_field == 0:
        if mant_field == 0:
            return sign, exp_field, mant_field, 0.0, "Zero"
        else:
            # Subnormal: 2^(1-1) * (0 + mant_field/2^1) = 1 * mant_field/2
            val = (mant_field / 2.0)
            return sign, exp_field, mant_field, val if sign_bit == 0 else -val, "Subnormal"
    else:
        # Normal: 2^(exp_field-1) * (1 + mant_field/2^1)
        val = (float(2**(exp_field - 1))) * (1 + mant_field / 2.0)
        return sign, exp_field, mant_field, val if sign_bit == 0 else -val, "Normal"

def decode_e3m2(bits):
    sign_bit = (bits >> 5) & 1
    exp_field = (bits >> 2) & 0x7
    mant_field = (bits & 0x3)
    sign = "-" if sign_bit else "+"

    if exp_field == 0:
        if mant_field == 0:
            return sign, exp_field, mant_field, 0.0, "Zero"
        else:
            # Subnormal: 2^(1-3) * (0 + mant_field/2^2) = 2^-2 * mant_field/4 = mant_field * 2^-4
            val = (2.0**-2) * (mant_field / 4.0)
            return sign, exp_field, mant_field, val if sign_bit == 0 else -val, "Subnormal"
    else:
        # Normal: 2^(exp_field-3) * (1 + mant_field/2^2)
        val = (2.0**(exp_field - 3)) * (1 + mant_field / 4.0)
        return sign, exp_field, mant_field, val if sign_bit == 0 else -val, "Normal"

def decode_e2m3(bits):
    sign_bit = (bits >> 5) & 1
    exp_field = (bits >> 3) & 0x3
    mant_field = (bits & 0x7)
    sign = "-" if sign_bit else "+"

    if exp_field == 0:
        if mant_field == 0:
            return sign, exp_field, mant_field, 0.0, "Zero"
        else:
            # Subnormal: 2^(1-1) * (0 + mant_field/2^3) = 1 * mant_field/8
            val = (mant_field / 8.0)
            return sign, exp_field, mant_field, val if sign_bit == 0 else -val, "Subnormal"
    else:
        # Normal: 2^(exp_field-1) * (1 + mant_field/2^3)
        val = (2.0**(exp_field - 1)) * (1 + mant_field / 8.0)
        return sign, exp_field, mant_field, val if sign_bit == 0 else -val, "Normal"

def decode_e4m3(bits):
    sign_bit = (bits >> 7) & 1
    exp_field = (bits >> 3) & 0xF
    mant_field = (bits & 0x7)
    sign = "-" if sign_bit else "+"

    if bits in [0x7F, 0xFF]:
        return sign, exp_field, mant_field, float('nan'), "NaN"

    if exp_field == 0:
        if mant_field == 0:
            return sign, exp_field, mant_field, 0.0, "Zero"
        else:
            # Subnormal: 2^(1-7) * (0 + mant_field/2^3) = 2^-6 * mant_field/8 = mant_field * 2^-9
            val = (2.0**-6) * (mant_field / 8.0)
            return sign, exp_field, mant_field, val if sign_bit == 0 else -val, "Subnormal"
    else:
        # Normal: 2^(exp_field-7) * (1 + mant_field/2^3)
        val = (2.0**(exp_field - 7)) * (1 + mant_field / 8.0)
        return sign, exp_field, mant_field, val if sign_bit == 0 else -val, "Normal"

def decode_e5m2(bits):
    sign_bit = (bits >> 7) & 1
    exp_field = (bits >> 2) & 0x1F
    mant_field = (bits & 0x3)
    sign = "-" if sign_bit else "+"

    if exp_field == 0x1F:
        if mant_field == 0:
            return sign, exp_field, mant_field, float('inf') if sign_bit == 0 else float('-inf'), "Infinity"
        else:
            return sign, exp_field, mant_field, float('nan'), "NaN"

    if exp_field == 0:
        if mant_field == 0:
            return sign, exp_field, mant_field, 0.0, "Zero"
        else:
            # Subnormal: 2^(1-15) * (0 + mant_field/2^2) = 2^-14 * mant_field/4
            val = (2.0**-14) * (mant_field / 4.0)
            return sign, exp_field, mant_field, val if sign_bit == 0 else -val, "Subnormal"
    else:
        # Normal: 2^(exp_field-15) * (1 + mant_field/2^2)
        val = (2.0**(exp_field - 15)) * (1 + mant_field / 4.0)
        return sign, exp_field, mant_field, val if sign_bit == 0 else -val, "Normal"

def decode_ue8m0(bits):
    if bits == 0xFF:
        return bits, "N/A", "N/A", "NaN", "Reserved"

    # Value = 2^(bits - 127)
    unbiased_exp = bits - 127
    val = 2.0**unbiased_exp
    return bits, bits, unbiased_exp, val, "Normal"

def format_value(val):
    if isinstance(val, float):
        if val == 0: return "0.0"
        if abs(val) >= 1e6 or (abs(val) < 1e-4 and val != 0):
            return f"{val:.10e}"
        return f"{val:.10f}".rstrip('0').rstrip('.')
    return str(val)

def generate_table_fp4():
    header = "| Binary | Hex | Sign | Exp | Mant | Value (Dec) | Notes |\n"
    header += "| :--- | :--- | :---: | :---: | :---: | :--- | :--- |\n"
    rows = []
    for i in range(16):
        s, e, m, val, note = decode_e2m1(i)
        binary = format(i, '04b')
        hex_val = f"0x{i:X}"
        val_str = format_value(val)
        rows.append(f"| `{binary}` | `{hex_val}` | `{s}` | `{e}` | `{m}` | `{val_str}` | {note} |")
    return header + "\n".join(rows)

def generate_table_fp6_e3m2():
    header = "| Binary | Hex | Sign | Exp | Mant | Value (Dec) | Notes |\n"
    header += "| :--- | :--- | :---: | :---: | :---: | :--- | :--- |\n"
    rows = []
    for i in range(64):
        s, e, m, val, note = decode_e3m2(i)
        binary = format(i, '06b')
        hex_val = f"0x{i:02X}"
        val_str = format_value(val)
        rows.append(f"| `{binary}` | `{hex_val}` | `{s}` | `{e}` | `{m}` | `{val_str}` | {note} |")
    return header + "\n".join(rows)

def generate_table_fp6_e2m3():
    header = "| Binary | Hex | Sign | Exp | Mant | Value (Dec) | Notes |\n"
    header += "| :--- | :--- | :---: | :---: | :---: | :--- | :--- |\n"
    rows = []
    for i in range(64):
        s, e, m, val, note = decode_e2m3(i)
        binary = format(i, '06b')
        hex_val = f"0x{i:02X}"
        val_str = format_value(val)
        rows.append(f"| `{binary}` | `{hex_val}` | `{s}` | `{e}` | `{m}` | `{val_str}` | {note} |")
    return header + "\n".join(rows)

def generate_table_fp8_e4m3():
    header = "| Binary | Hex | Sign | Exp | Mant | Value (Dec) | Notes |\n"
    header += "| :--- | :--- | :---: | :---: | :---: | :--- | :--- |\n"
    rows = []
    for i in range(256):
        s, e, m, val, note = decode_e4m3(i)
        binary = format(i, '08b')
        hex_val = f"0x{i:02X}"
        val_str = format_value(val)
        rows.append(f"| `{binary}` | `{hex_val}` | `{s}` | `{e}` | `{m}` | `{val_str}` | {note} |")
    return header + "\n".join(rows)

def generate_table_fp8_e5m2():
    header = "| Binary | Hex | Sign | Exp | Mant | Value (Dec) | Notes |\n"
    header += "| :--- | :--- | :---: | :---: | :---: | :--- | :--- |\n"
    rows = []
    for i in range(256):
        s, e, m, val, note = decode_e5m2(i)
        binary = format(i, '08b')
        hex_val = f"0x{i:02X}"
        val_str = format_value(val)
        rows.append(f"| `{binary}` | `{hex_val}` | `{s}` | `{e}` | `{m}` | `{val_str}` | {note} |")
    return header + "\n".join(rows)

def generate_table_ue8m0():
    header = "| Binary | Hex | Biased Exp | Unbiased | Value ($2^{E-127}$) | Notes |\n"
    header += "| :--- | :--- | :---: | :---: | :--- | :--- |\n"
    rows = []
    for i in range(256):
        b, be, ue, val, note = decode_ue8m0(i)
        binary = format(i, '08b')
        hex_val = f"0x{i:02X}"
        val_str = format_value(val)
        rows.append(f"| `{binary}` | `{hex_val}` | `{be}` | `{ue}` | `{val_str}` | {note} |")
    return header + "\n".join(rows)

if __name__ == "__main__":
    os.makedirs("docs/reference", exist_ok=True)

    with open("docs/reference/LOOKUP_TABLES.md", "w") as f:
        f.write("# OCP MX Data Lookup Tables\n\n")
        f.write("This document provides detailed value tables for all supported OCP MX floating-point formats.\n\n")

        f.write("## Table of Contents\n")
        f.write("1. [FP4 (E2M1) Table](#fp4-e2m1-table)\n")
        f.write("2. [FP6 (E3M2) Table](#fp6-e3m2-table)\n")
        f.write("3. [FP6 (E2M3) Table](#fp6-e2m3-table)\n")
        f.write("4. [FP8 (E4M3) Table](#fp8-e4m3-table)\n")
        f.write("5. [FP8 (E5M2) Table](#fp8-e5m2-table)\n")
        f.write("6. [Shared Scale (UE8M0) Table](#shared-scale-ue8m0-table)\n\n")

        f.write("---\n\n")

        f.write("## FP4 (E2M1) Table\n\n")
        f.write("Format: [3] Sign, [2:1] Exponent (Bias 1), [0] Mantissa\n\n")
        f.write(generate_table_fp4())
        f.write("\n\n---\n\n")

        f.write("## FP6 (E3M2) Table\n\n")
        f.write("Format: [5] Sign, [4:2] Exponent (Bias 3), [1:0] Mantissa\n\n")
        f.write(generate_table_fp6_e3m2())
        f.write("\n\n---\n\n")

        f.write("## FP6 (E2M3) Table\n\n")
        f.write("Format: [5] Sign, [4:3] Exponent (Bias 1), [2:0] Mantissa\n\n")
        f.write(generate_table_fp6_e2m3())
        f.write("\n\n---\n\n")

        f.write("## FP8 (E4M3) Table\n\n")
        f.write("Format: [7] Sign, [6:3] Exponent (Bias 7), [2:0] Mantissa\n\n")
        f.write(generate_table_fp8_e4m3())
        f.write("\n\n---\n\n")

        f.write("## FP8 (E5M2) Table\n\n")
        f.write("Format: [7] Sign, [6:2] Exponent (Bias 15), [1:0] Mantissa\n\n")
        f.write(generate_table_fp8_e5m2())
        f.write("\n\n---\n\n")

        f.write("## Shared Scale (UE8M0) Table\n\n")
        f.write("Format: 8-bit Unsigned Biased Exponent (Bias 127)\n\n")
        f.write(generate_table_ue8m0())
        f.write("\n")
