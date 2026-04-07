#!/bin/bash
# test/run_tests.sh

set -e

# Directory for waveforms and results
WAVEFORM_DIR="waveforms"
RESULTS_DIR="results"
mkdir -p "$WAVEFORM_DIR"
mkdir -p "$RESULTS_DIR"

# Clean previous builds
make clean

# Modules to test - if not set from outside, use default
if [ -z "$COCOTB_TEST_MODULES" ]; then
    COCOTB_MODULES="test test_coverage test_performance test_short_protocol test_exhaustive"
else
    # Convert comma-separated list to space-separated
    COCOTB_MODULES=$(echo $COCOTB_TEST_MODULES | tr ',' ' ')
fi

FAILED=0

for module in $COCOTB_MODULES; do
    echo "Processing module: $module"

    # Extract test cases from the python file
    # Improved discovery: look for @cocotb.test then the next async def
    # This sed script finds @cocotb.test and then extracts the name from the next async def
    tests=$(sed -n '/@cocotb\.test/{n;s/async def \([a-zA-Z0-9_]*\).*/\1/p}' "${module}.py")

    for test in $tests; do
        echo "Running test: $module.$test"

        # Clean the local tb.fst and results.xml if they exist
        rm -f tb.fst results.xml

        # Run the specific test
        # Use MODULE and TESTCASE as used in the project's Makefile
        if ! make MODULE=$module TESTCASE=$test; then
            echo "Test $module.$test FAILED"
            FAILED=1
        fi

        # Check if tb.fst was generated
        if [ -f "tb.fst" ]; then
            # Move and rename FST
            mv tb.fst "$WAVEFORM_DIR/${module}.${test}.fst"

            # Convert to VCD
            fst2vcd "$WAVEFORM_DIR/${module}.${test}.fst" -o "$WAVEFORM_DIR/${module}.${test}.vcd"
            echo "Generated $WAVEFORM_DIR/${module}.${test}.vcd"
        else
            echo "Warning: tb.fst not found for $module.$test"
        fi

        # Preserve results.xml
        if [ -f "results.xml" ]; then
            mv results.xml "$RESULTS_DIR/results_${module}.${test}.xml"
        fi
    done
done

if [ $FAILED -ne 0 ]; then
    echo "One or more tests failed."
    exit 1
fi

echo "All tests passed."
exit 0
