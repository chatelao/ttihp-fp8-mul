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

    with open("docs/reference/FP4_E2M1_TABLE.md", "w") as f:
        f.write("# OCP MX FP4 (E2M1) Value Table\n\n")
        f.write("Format: [3] Sign, [2:1] Exponent (Bias 1), [0] Mantissa\n\n")
        f.write(generate_table_fp4())

    with open("docs/reference/FP8_E4M3_TABLE.md", "w") as f:
        f.write("# OCP MX FP8 (E4M3) Value Table\n\n")
        f.write("Format: [7] Sign, [6:3] Exponent (Bias 7), [2:0] Mantissa\n\n")
        f.write(generate_table_fp8_e4m3())

    with open("docs/reference/FP8_E5M2_TABLE.md", "w") as f:
        f.write("# OCP MX FP8 (E5M2) Value Table\n\n")
        f.write("Format: [7] Sign, [6:2] Exponent (Bias 15), [1:0] Mantissa\n\n")
        f.write(generate_table_fp8_e5m2())

    with open("docs/reference/UFP8_E8M0_TABLE.md", "w") as f:
        f.write("# OCP MX UFP8 (UE8M0) Value Table (Shared Scale)\n\n")
        f.write("Format: 8-bit Unsigned Biased Exponent (Bias 127)\n\n")
        f.write(generate_table_ue8m0())
