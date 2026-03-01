import sys
import os

# Add src and test to path
sys.path.append(os.path.abspath("src"))
sys.path.append(os.path.abspath("test"))

from test import decode_format, align_product_model

def test_nan_propagation():
    print("Testing NaN Propagation Model...")
    # E5M2: NaN is Exp=31, Mant!=0. 0x7E is NaN (sign=0, exp=31, mant=2)
    # E5M2: 1.0 is 0x3C (sign=0, exp=15, mant=0)

    # NaN * 1.0 = NaN
    prod, nan, inf, sign = align_product_model(0x7E, 0x3C, 1, 1, support_e5m2=True)
    assert nan == True
    assert inf == False
    print("  NaN * 1.0 = NaN: PASSED")

    # 1.0 * NaN = NaN
    prod, nan, inf, sign = align_product_model(0x3C, 0x7E, 1, 1, support_e5m2=True)
    assert nan == True
    print("  1.0 * NaN = NaN: PASSED")

    # Inf * 0.0 = NaN
    # E5M2: Inf is 0x7C, 0.0 is 0x00
    prod, nan, inf, sign = align_product_model(0x7C, 0x00, 1, 1, support_e5m2=True)
    assert nan == True
    print("  Inf * 0.0 = NaN: PASSED")

def test_inf_propagation():
    print("Testing Inf Propagation Model...")
    # E5M2: Inf is 0x7C
    # E5M2: 1.0 is 0x3C

    # Inf * 1.0 = Inf
    prod, nan, inf, sign = align_product_model(0x7C, 0x3C, 1, 1, support_e5m2=True)
    assert nan == False
    assert inf == True
    assert sign == 0
    print("  Inf * 1.0 = Inf: PASSED")

    # -1.0 * Inf = -Inf
    # -1.0 is 0xBC
    prod, nan, inf, sign = align_product_model(0xBC, 0x7C, 1, 1, support_e5m2=True)
    assert inf == True
    assert sign == 1
    print("  -1.0 * Inf = -Inf: PASSED")

def test_inf_sign_conflict():
    print("Testing Infinity Sign Conflict (Inf + (-Inf) = NaN)...")
    # This logic is implemented in project.v but we can verify the concept in the model test
    # by simulating the lane combination logic.

    # Lane 0: +Inf (from 1.0 * Inf)
    _, nan0, inf0, sign0 = align_product_model(0x3C, 0x7C, 1, 1, support_e5m2=True)

    # Lane 1: -Inf (from -1.0 * Inf)
    _, nan1, inf1, sign1 = align_product_model(0xBC, 0x7C, 1, 1, support_e5m2=True)

    # Combination logic from project.v:
    inf_sign_conflict = inf0 and inf1 and (sign0 != sign1)
    nan_combined = nan0 or nan1 or inf_sign_conflict

    assert inf_sign_conflict == True
    assert nan_combined == True
    print("  Inf + (-Inf) -> NaN: PASSED")

if __name__ == "__main__":
    try:
        test_nan_propagation()
        test_inf_propagation()
        test_inf_sign_conflict()
        print("\nAll model tests PASSED.")
    except AssertionError as e:
        print(f"\nModel test FAILED: {e}")
        sys.exit(1)
