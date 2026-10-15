#!/usr/bin/env bash
# Convenience entry point: runs the automated test suite (see tools/run_tests.sh).
#   ./run_tests.sh [all|quick|lan|steam]
exec "$(dirname "$0")/tools/run_tests.sh" "$@"
