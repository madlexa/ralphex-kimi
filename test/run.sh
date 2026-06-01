#!/usr/bin/env bash
# Run all ralphex-kimi tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================"
echo "ralphex-kimi test suite"
echo "========================================"
echo ""

exit_code=0

bash "$SCRIPT_DIR/test_wrapper.sh" || exit_code=$?
echo ""
bash "$SCRIPT_DIR/test_install.sh" || exit_code=$?

echo ""
echo "========================================"
if [[ "$exit_code" -eq 0 ]]; then
  echo "All tests passed!"
else
  echo "Some tests failed."
fi
echo "========================================"

exit "$exit_code"
