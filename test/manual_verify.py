
def align_reference(prod, exp_sum, sign):
    # exp_sum is signed 7-bit
    if exp_sum >= 64:
        exp_sum_val = exp_sum - 128
    else:
        exp_sum_val = exp_sum

    # Mathematical value
    # value = (prod / 64.0) * (2.0 ** (exp_sum_val - 7))
    # fixed_point = value * 256
    # fixed_point = (prod / 64.0) * (2.0 ** (exp_sum_val - 7)) * 256
    # fixed_point = prod * 2^-6 * 2^(exp_sum_val - 7) * 2^8
    # fixed_point = prod * 2^(exp_sum_val - 6 - 7 + 8) = prod * 2^(exp_sum_val - 5)

    shift_amt = exp_sum_val - 5
    if shift_amt >= 0:
        res = prod << shift_amt
    else:
        res = prod >> (-shift_amt)

    mask = 0xFFFFFFFF
    if sign:
        return (-res) & mask
    else:
        return res & mask

def test():
    cases = [
        (64, 7, 0, 256),    # 1.0 * 1.0 = 1.0 (0x100)
        (64, 7, 1, 0xFFFFFF00), # -1.0
        (64, 13, 0, 16384), # 1.0 * 2^6 = 64.0 (0x4000)
        (225, 21, 0, 225 << 16), # max * max
        (1, 1, 0, 1 >> 4), # subnormal small
    ]

    for prod, exp_sum, sign, expected in cases:
        actual = align_reference(prod, exp_sum, sign)
        print(f"prod={prod}, exp_sum={exp_sum}, sign={sign} -> actual=0x{actual:08x}, expected=0x{expected:08x}")
        assert actual == expected

if __name__ == "__main__":
    test()
    print("Manual verification passed!")
