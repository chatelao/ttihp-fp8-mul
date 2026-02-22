
import math

def float8_to_val(bits):
    s = (bits >> 7) & 1
    e = (bits >> 3) & 0xF
    m = bits & 0x7
    sign = -1 if s else 1
    if e == 0:
        if m == 0:
            return 0.0 * sign
        else:
            # Subnormal: 0.mmm * 2^(1-7)
            return sign * (m / 8.0) * (2 ** -6)
    elif e == 15:
        if m == 0:
            return float('inf') * sign
        else:
            return float('nan')
    else:
        # Normal: 1.mmm * 2^(e-7)
        return sign * (1 + m / 8.0) * (2 ** (e - 7))

def val_to_float8_rne(val):
    if math.isnan(val):
        return 0x7F # canonical NaN

    sign = 1 if math.copysign(1.0, val) < 0 else 0
    abs_val = abs(val)

    if abs_val == 0:
        return (sign << 7)

    if abs_val >= (1.875 + 0.0625) * (2**7): # Overflow to Infinity
        return (sign << 7) | 0x78

    if abs_val >= 2**-6:
        # Normal range
        exp = int(math.floor(math.log2(abs_val)))
        e = exp + 7
        if e >= 15: # Overflow to infinity
            return (sign << 7) | 0x78

        # Significand
        mant_scaled = (abs_val / (2**exp)) * 8
        m_int = int(math.floor(mant_scaled))
        rem = mant_scaled - m_int

        # Round to nearest even
        if rem > 0.5 or (rem == 0.5 and (m_int % 2 == 1)):
            m_int += 1

        if m_int == 8:
            m_int = 0
            e += 1
            if e >= 15:
                return (sign << 7) | 0x78

        # Since we might have rounded up into a normal from a subnormal or vice versa
        # but here we are already in normal.
        return (sign << 7) | (e << 3) | (m_int & 0x7)
    else:
        # Subnormal range
        mant_scaled = (abs_val / (2**-6)) * 8
        m_int = int(math.floor(mant_scaled))
        rem = mant_scaled - m_int

        # Round to nearest even
        if rem > 0.5 or (rem == 0.5 and (m_int % 2 == 1)):
            m_int += 1

        if m_int == 8:
            return (sign << 7) | (1 << 3) | 0 # Smallest normal

        return (sign << 7) | (0 << 3) | m_int

def fp8_mul_ieee(a_bits, b_bits):
    va = float8_to_val(a_bits)
    vb = float8_to_val(b_bits)

    if math.isnan(va) or math.isnan(vb):
        return 0x7F

    res = va * vb
    return val_to_float8_rne(res)

# Reference from project.v logic (transcribed)
def fp8_mul_project_v(a, b):
    sign1 = (a >> 7) & 1
    exp1 = (a >> 3) & 0xF
    mant1 = a & 0x7
    sign2 = (b >> 7) & 1
    exp2 = (b >> 3) & 0xF
    mant2 = b & 0x7
    isnan1 = (exp1 == 15 and mant1 != 0)
    isnan2 = (exp2 == 15 and mant2 != 0)
    isnan = isnan1 or isnan2
    m1 = ((1 << 3) | mant1) if exp1 != 0 else mant1
    m2 = ((1 << 3) | mant2) if exp2 != 0 else mant2
    full_mant = (m1 * m2) & 0xFF
    overflow_mant = (full_mant >> 7) & 1
    if overflow_mant:
        shifted_mant = full_mant & 0x7F
    else:
        shifted_mant = (full_mant << 1) & 0x7F
    exp_sum = exp1 + exp2 + overflow_mant
    roundup = (exp_sum < 8 and shifted_mant != 0) or \
              (((shifted_mant >> 4) & 0x7) == 7 and ((shifted_mant >> 3) & 1))
    underflow = exp_sum < (8 - (1 if roundup else 0))
    is_zero = (exp1 == 0 or exp2 == 0 or underflow)
    exp_sum_with_roundup = exp_sum + (1 if roundup else 0)
    if exp_sum_with_roundup < 7:
        exp_out_tmp = 0
    else:
        exp_out_tmp = exp_sum_with_roundup - 7
    if isnan:
        exp_out = 15
    elif exp_out_tmp > 15:
        exp_out = 15
    elif is_zero:
        exp_out = 0
    else:
        exp_out = exp_out_tmp & 0xF
    if isnan:
        mant_out = 7
    elif exp_out_tmp > 15:
        mant_out = 7
    elif is_zero or roundup:
        mant_out = 0
    else:
        m_hi = (shifted_mant >> 4) & 0x7
        m_lo = shifted_mant & 0xF
        inc = 1 if (m_lo > 8 or (m_lo == 8 and (m_hi & 1))) else 0
        mant_out = (m_hi + inc) & 0x7
    if isnan:
        sign_out = sign1 if isnan1 else sign2
    else:
        sign_out = sign1 ^ sign2
    return (sign_out << 7) | (exp_out << 3) | mant_out

# Compare
mismatches = 0
for a in range(256):
    for b in range(256):
        ideal = fp8_mul_ieee(a, b)
        actual = fp8_mul_project_v(a, b)
        if ideal != actual:
            # Check if it's just NaN representation difference
            if (ideal & 0x7F) == 0x7F and (actual & 0x7F) == 0x7F:
                continue
            # Check if it's both zero
            if (ideal & 0x7F) == 0 and (actual & 0x7F) == 0:
                continue

            mismatches += 1
            if mismatches < 10:
                print(f"Mismatch at {a:02x}, {b:02x}: Ideal={ideal:02x} ({float8_to_val(ideal)}), Actual={actual:02x} ({float8_to_val(actual)})")

print(f"Total mismatches: {mismatches}")
