
def decode_format(bits, format_val):
    if format_val == 0: # E4M3
        sign = (bits >> 7) & 1
        exp = (bits >> 3) & 0xF
        mant = (bits & 0x7)
        bias = 7
        is_int = False
    elif format_val == 1: # E5M2
        sign = (bits >> 7) & 1
        exp = (bits >> 2) & 0x1F
        mant = (bits & 0x3) << 1
        bias = 15
        is_int = False
    elif format_val == 2: # INT8
        sign = (bits >> 7) & 1
        val = bits if bits < 128 else bits - 256
        mant = abs(val)
        exp = 0
        bias = 3
        is_int = True
    elif format_val == 3: # INT8_SYM
        sign = (bits >> 7) & 1
        val = bits if bits < 128 else bits - 256
        if val == -128: val = -127
        mant = abs(val)
        exp = 0
        bias = 3
        is_int = True
    else: # Default E4M3
        return decode_format(bits, 0)

    return sign, exp, mant, bias, is_int

def test_formats():
    print("Testing format decoding...")
    # E4M3: 1.0 (0x38)
    s, e, m, b, is_int = decode_format(0x38, 0)
    assert s == 0 and e == 7 and m == 0 and b == 7 and not is_int

    # E5M2: 1.0 (0x3C)
    s, e, m, b, is_int = decode_format(0x3C, 1)
    assert s == 0 and e == 15 and m == 0 and b == 15 and not is_int

    # INT8: 64 (0x40)
    s, e, m, b, is_int = decode_format(0x40, 2)
    assert s == 0 and e == 0 and m == 64 and b == 3 and is_int

    # INT8_SYM: -128 -> -127 (0x80)
    s, e, m, b, is_int = decode_format(0x80, 3)
    assert s == 1 and e == 0 and m == 127 and b == 3 and is_int
    print("Format decoding tests passed!")

def align_reference(prod, exp_sum, sign):
    # exp_sum is signed 10-bit in current design
    exp_sum_val = exp_sum
    if exp_sum_val > 511: exp_sum_val -= 1024

    shift_amt = exp_sum_val - 5

    if shift_amt >= 0:
        res = prod << shift_amt
        magnitude_overflow = (res >= 0x80000000)
    else:
        n = -shift_amt
        res = prod >> n
        magnitude_overflow = (res >= 0x80000000) # Should not happen for right shift of 32-bit prod unless it was large

    if sign:
        # Saturation to -2^31
        if magnitude_overflow and res > 0x80000000:
            return 0x80000000
        else:
            return (-res) & 0xFFFFFFFF
    else:
        # Saturation to 2^31-1
        if magnitude_overflow:
            return 0x7FFFFFFF
        else:
            return res & 0xFFFFFFFF

def test():
    cases = [
        (64, 7, 0, 256),    # 1.0 * 1.0 = 1.0 (0x100)
        (64, 7, 1, 0xFFFFFF00), # -1.0
        (64, 13, 0, 16384), # 1.0 * 2^6 = 64.0 (0x4000)
        (225, 21, 0, 225 << 16), # max * max
        (1, 1, 0, 0), # subnormal small
        (0x80000000, 5, 1, 0x80000000), # Exact -2^31
        (0x80000001, 5, 1, 0x80000000), # Saturation to -2^31
        (0x7FFFFFFF, 5, 0, 0x7FFFFFFF), # Exact 2^31-1
        (0x80000000, 5, 0, 0x7FFFFFFF), # Saturation to 2^31-1
    ]

    for prod, exp_sum, sign, expected in cases:
        actual = align_reference(prod, exp_sum, sign)
        print(f"prod={prod}, exp_sum={exp_sum}, sign={sign} -> actual=0x{actual:08x}, expected=0x{expected:08x}")
        assert actual == expected

if __name__ == "__main__":
    test_formats()
    test()
    print("Manual verification passed!")
