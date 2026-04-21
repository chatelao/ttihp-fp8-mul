import struct

def to_f32_bits(val_fixed, shared_exp_val, sign_bit):
    val_float = (abs(val_fixed) / (2.0**16)) * (2.0 ** shared_exp_val)
    if sign_bit: val_float = -val_float
    return struct.unpack('>I', struct.pack('>f', val_float))[0]

# test_mxplus_yaml case 1:
# Expected Fixed = 10240. Binary point 16.
# 10240 / 65536 = 0.15625.
# Float32 of 0.15625 is 0x3E200000.
print(f"0.15625 -> {hex(to_f32_bits(10240, 0, False))}")
