# Change Log - IEEE 754 Binary32 Migration

This document details the major architectural change from 32-bit signed fixed-point output to standard IEEE 754 Binary32 (Float32) output.

## Overview

Previously, the MAC unit produced results in a 32-bit signed fixed-point format with 8 fractional bits (Q23.8). To align with OCP (Open Compute Project) specifications and industry standards, the output stage has been modified to convert this internal representation into a 32-bit floating-point bit pattern (IEEE 754 Binary32).

Internal accumulation continues to use 32-bit signed fixed-point logic to maintain precision ($2^{-8}$) and simplify the datapath, with a single conversion stage added before the final serialization.

## Format Comparison

The following table compares the 32-bit bit patterns for key values before and after the migration.

| Logical Value | Fixed-Point (Before, Q23.8) | Binary32 (After, Float32) | Description |
| :--- | :--- | :--- | :--- |
| **Max Positive** | `0x7FFFFFFF` | `0x4A7FFFFF` | Maximum representable value ($\approx 8,388,607.996$) |
| **1.0** | `0x00000100` | `0x3F800000` | Unit value |
| **0.0** | `0x00000000` | `0x00000000` | Zero |
| **-1.0** | `0xFFFFFF00` | `0xBF800000` | Negative unit |
| **Min Negative** | `0x80000000` | `0xCB000000` | Minimum representable value ($-8,388,608.0$) |
| **+Infinity** | N/A | `0x7F800000` | Standard IEEE 754 Infinity |
| **-Infinity** | N/A | `0xFF800000` | Standard IEEE 754 Negative Infinity |
| **NaN** | N/A | `0x7FC00000` | Standard IEEE 754 Quiet NaN |

## Implementation Details

The conversion logic implemented in `src/project.v` performs the following steps:
1. **Sign Extraction**: Detects if the result is negative.
2. **Absolute Value**: Operates on the magnitude for normalization.
3. **Leading Zero Detection**: Uses a priority encoder to find the first '1' bit.
4. **Normalization**: Shifts the mantissa left to remove leading zeros.
5. **Exponent Calculation**: Offsets the base bias (127) by the fixed-point fractional bit count (8) and the leading zero position.
6. **Exception Overrides**: Overrides the calculated result with standard patterns if the internal `nan_sticky`, `inf_pos_sticky`, or `inf_neg_sticky` flags are set.

## Verification

The migration has been verified across all build configurations (Full, Lite, Tiny, Ultra-Tiny, Tiny-Serial) using a refined Python model in `test/test.py` that accurately mimics the hardware's fixed-to-float conversion and saturation behaviors.
