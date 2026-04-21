import struct

def to_f32_bits(val_fixed, shared_exp_val, sign_bit):
    val_float = (abs(val_fixed) / (2.0**16)) * (2.0 ** shared_exp_val)
    if sign_bit: val_float = -val_float
    return struct.unpack('>I', struct.pack('>f', val_float))[0]

# test_mxfp4_input_buffering:
# Elements 0x22 (E2M1). ma=1, mb=1. prod=1. sa=127, sb=127.
# exp_sum = 1 + 1 - (1 + 1 - 7) = 2 - (-5) = 7.
# shift = 7 + 3 = 10.
# aligned = 1 << 10 = 1024.
# Total 32 elements: 32 * 1024 = 32768.
# bits 16 is 2^0, so 32768 is 0.5.
# shared_exp = 127 + 127 - 254 = 0.
# Float32 of 0.5 is 0x3F000000.
print(f"0.5 -> {hex(to_f32_bits(32768, 0, False))}")
