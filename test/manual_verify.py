
def align_reference(prod, exp_sum, sign):
    # exp_sum is signed 7-bit (legacy, now 10-bit in RTL but manual_verify uses it for basic cases)
    if exp_sum >= 512:
        exp_sum_val = exp_sum - 1024
    elif exp_sum >= 64 and exp_sum < 512: # Handle 7-bit signed for backward compat
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
    WIDTH = 40

    huge = False
    if shift_amt >= 0:
        if shift_amt >= WIDTH and prod != 0:
            huge = True
            res = (1 << WIDTH) - 1
        else:
            if shift_amt > 0 and (prod >> (WIDTH - shift_amt)) != 0:
                huge = True
            res = prod << shift_amt
    else:
        n = -shift_amt
        if n >= WIDTH:
            res = 0
        else:
            res = prod >> n

    mask = 0xFFFFFFFF

    if sign:
        # Saturation check matching RTL
        if (huge or (res >> 32) != 0 or ((res & (1 << 31)) != 0 and (res & ((1 << 31) - 1)) != 0)):
            return 0x80000000
        return (-res) & mask
    else:
        if (huge or (res >> 31) != 0):
            return 0x7FFFFFFF
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
