#!/bin/bash
# test/run_tests.sh

# test/run_tests.sh

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

    # Robust test discovery using Python
    tests=$(python3 list_tests.py "$module")

    if [ -z "$tests" ]; then
        echo "No tests found in $module"
        continue
    fi

    for test in $tests; do
        echo "Running test: $module.$test"

        # Clean local artifacts
        rm -f tb.vcd tb_accumulator.vcd tb_aligner.vcd results.xml

        # Explicitly set TESTCASE to avoid infinite recursion in Makefile
        export TESTCASE=$test

        # Run the specific test
        if ! make GATES=$GATES MODULE=$module TESTCASE=$test; then
            echo "Test $module.$test FAILED"
            FAILED=1
        fi

        # Handle multiple possible waveform names
        for vcd in tb.vcd tb_accumulator.vcd tb_aligner.vcd; do
            if [ -f "$vcd" ]; then
                mv "$vcd" "$WAVEFORM_DIR/${module}.${test}.${vcd}"
                echo "Generated $WAVEFORM_DIR/${module}.${test}.${vcd}"
            fi
        done

        # Preserve results.xml
        if [ -f "results.xml" ]; then
            mv results.xml "$RESULTS_DIR/results_${module}.${test}.xml"
        fi
    done
done

# Generate consolidated results.xml for CI
# We prioritize the real individual results if they exist, otherwise fallback to a dummy
if ls "$RESULTS_DIR"/results_*.xml >/dev/null 2>&1; then
    # Create a consolidated results.xml by concatenating testsuites
    # This is a bit of a hack but satisfies many JUnit parsers
    echo '<?xml version="1.0" encoding="utf-8"?><testsuites>' > results.xml
    for f in "$RESULTS_DIR"/results_*.xml; do
        # Extract the content between <testsuite> and </testsuite>
        # Use a more robust sed pattern to handle potential XML variations
        sed -n '/<testsuite/,/<\/testsuite>/p' "$f" >> results.xml
    done
    echo '</testsuites>' >> results.xml
else
    if [ $FAILED -ne 0 ]; then
        echo '<?xml version="1.0" encoding="utf-8"?><testsuites><testsuite name="all_tests" tests="1" errors="0" failures="1" skipped="0" time="0"><testcase classname="all" name="bulk_run" time="0"><failure message="One or more tests failed"/></testcase></testsuite></testsuites>' > results.xml
    else
        echo '<?xml version="1.0" encoding="utf-8"?><testsuites><testsuite name="all_tests" tests="1" errors="0" failures="0" skipped="0" time="0"><testcase classname="all" name="bulk_run" time="0"/></testsuite></testsuites>' > results.xml
    fi
fi

if [ $FAILED -ne 0 ]; then
    echo "One or more tests failed."
    exit 1
else
    echo "All tests passed."
    exit 0
fi
