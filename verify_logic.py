import os
import sys

# Mock cocotb
class MockLog:
    def info(self, msg): print(f"INFO: {msg}")
    def error(self, msg): print(f"ERROR: {msg}")
    def warning(self, msg): print(f"WARNING: {msg}")

# Import functions from test.py
# We need to handle the imports in test.py
with open('test/test.py', 'r') as f:
    code = f.read()
    # Remove cocotb imports and decorators
    code = code.replace('import cocotb', '')
    code = code.replace('from cocotb.clock import Clock', '')
    code = code.replace('from cocotb.triggers import ClockCycles, Timer', '')
    code = code.replace('@cocotb.test()', '')
    # Mock Timer and ClockCycles
    code = "def Timer(*args, **kwargs): pass\ndef ClockCycles(*args, **kwargs): pass\n" + code

exec(code, globals())

# Test decode_format for NaN/Inf
print("Testing decode_format...")
# E5M2: 0x7C is Inf, 0x7D is NaN
s, e, m, b, is_int, nan, inf = decode_format(0x7C, 1)
print(f"E5M2 0x7C: nan={nan}, inf={inf}")
assert inf == True and nan == False

s, e, m, b, is_int, nan, inf = decode_format(0x7D, 1)
print(f"E5M2 0x7D: nan={nan}, inf={inf}")
assert nan == True and inf == False

# E4M3: 0x7F is NaN
s, e, m, b, is_int, nan, inf = decode_format(0x7F, 0)
print(f"E4M3 0x7F: nan={nan}, inf={inf}")
assert nan == True

# Test align_product_model propagation
print("Testing align_product_model propagation...")
# Inf * 1.0 = Inf
res = align_product_model(0x7C, 0x3C, 1, 1)
print(f"Inf * 1.0: {res}")
assert res == 0x7FFFFFFF # Max saturation for Inf

# Inf * 0.0 = NaN
res = align_product_model(0x7C, 0x00, 1, 1)
print(f"Inf * 0.0: {res}")
assert res == 0x7FFFFFFF # Max saturation for NaN

# NaN * 1.0 = NaN
res = align_product_model(0x7D, 0x3C, 1, 1)
print(f"NaN * 1.0: {res}")
assert res == 0x7FFFFFFF

print("Logic verification SUCCESS")
