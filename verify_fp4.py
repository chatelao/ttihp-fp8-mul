def decode_fp4(bits):
    sign = (bits >> 3) & 1
    exp_field = (bits >> 1) & 3
    mant_field = bits & 1
    if exp_field == 0:
        val = 0.5 * mant_field
    else:
        val = (2**exp_field) * (1 + 0.5 * mant_field) / 2.0
    return -val if sign else val

total_sum = 0
for i in range(16):
    val = decode_fp4(i)
    total_sum += val * val
print(f"Sum for 16: {total_sum}")
print(f"Sum for 32: {total_sum * 2}")
print(f"Fixed (8 bits): {int(total_sum * 2 * 256)} (0x{int(total_sum * 2 * 256):08X})")
