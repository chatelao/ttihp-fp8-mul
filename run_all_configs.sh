for config in Full Lite Tiny Ultra-Tiny Tiny-Serial; do
  echo "Running config: $config"
  cd test
  make clean > /dev/null 2>&1
  if [ "$config" == "Full" ]; then
    export COMPILE_ARGS="-P tb.ALIGNER_WIDTH=40 -P tb.ACCUMULATOR_WIDTH=40 -P tb.SUPPORT_E5M2=1 -P tb.SUPPORT_MXFP6=1 -P tb.SUPPORT_MXFP4=1 -P tb.SUPPORT_INT8=1 -P tb.SUPPORT_PIPELINING=1 -P tb.SUPPORT_ADV_ROUNDING=1 -P tb.SUPPORT_MIXED_PRECISION=1 -P tb.ENABLE_SHARED_SCALING=1 -P tb.SUPPORT_SERIAL=0 -P tb.SERIAL_K_FACTOR=1"
  elif [ "$config" == "Lite" ]; then
    export COMPILE_ARGS="-P tb.ALIGNER_WIDTH=40 -P tb.ACCUMULATOR_WIDTH=40 -P tb.SUPPORT_E5M2=1 -P tb.SUPPORT_MXFP6=0 -P tb.SUPPORT_MXFP4=1 -P tb.SUPPORT_INT8=1 -P tb.SUPPORT_PIPELINING=1 -P tb.SUPPORT_ADV_ROUNDING=0 -P tb.SUPPORT_MIXED_PRECISION=1 -P tb.ENABLE_SHARED_SCALING=1 -P tb.SUPPORT_SERIAL=0 -P tb.SERIAL_K_FACTOR=1"
  elif [ "$config" == "Tiny" ]; then
    export COMPILE_ARGS="-P tb.ALIGNER_WIDTH=40 -P tb.ACCUMULATOR_WIDTH=40 -P tb.SUPPORT_E5M2=0 -P tb.SUPPORT_MXFP6=0 -P tb.SUPPORT_MXFP4=1 -P tb.SUPPORT_INT8=0 -P tb.SUPPORT_PIPELINING=0 -P tb.SUPPORT_ADV_ROUNDING=0 -P tb.SUPPORT_MIXED_PRECISION=0 -P tb.ENABLE_SHARED_SCALING=0 -P tb.SUPPORT_SERIAL=0 -P tb.SERIAL_K_FACTOR=1"
  elif [ "$config" == "Ultra-Tiny" ]; then
    export COMPILE_ARGS="-P tb.SUPPORT_SERIAL=0 -P tb.SERIAL_K_FACTOR=1"
  elif [ "$config" == "Tiny-Serial" ]; then
    export COMPILE_ARGS="-P tb.SUPPORT_SERIAL=1 -P tb.SERIAL_K_FACTOR=64"
  fi
  make
  if [ ! -f results.xml ]; then
    echo "Error: $config results.xml not found. Simulation may have failed to run."
  elif grep -q failure results.xml; then
    echo "$config FAILED in results.xml"
    grep failure results.xml
  else
    echo "$config PASSED"
  fi
  cd ..
done
