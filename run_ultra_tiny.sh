export COCOTB_TEST_MODULES=test,test_coverage,test_performance,test_short_protocol,test_exhaustive
export COMPILE_ARGS="-Ptb.ACCUMULATOR_WIDTH=24 -Ptb.ALIGNER_WIDTH=32 -Ptb.SUPPORT_E5M2=0 -Ptb.SUPPORT_MXFP6=0 -Ptb.SUPPORT_PIPELINING=0 -Ptb.ENABLE_SHARED_SCALING=0"
cd test
make clean
make
