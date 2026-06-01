#!/usr/bin/env bash
# Tests for kimi-as-claude.sh wrapper

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WRAPPER="$PROJECT_DIR/kimi-as-claude.sh"
STUB_DIR="$PROJECT_DIR/test/stubs"

# colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

passed=0
failed=0

run_test() {
  local name="$1"
  local scenario="$2"
  local expected_text="${3:-}"
  local expected_exit="${4:-0}"
  local verbose="${5:-0}"

  local output
  local exit_code=0

  output=$(PATH="$STUB_DIR:$PATH" KIMI_STUB_SCENARIO="$scenario" KIMI_VERBOSE="$verbose" bash "$WRAPPER" <<< "test prompt" 2>&1) || exit_code=$?

  if [[ "$exit_code" -ne "$expected_exit" ]]; then
    echo -e "${RED}FAIL${NC} $name: expected exit $expected_exit, got $exit_code"
    echo "  output: $output"
    ((failed++)) || true
    return
  fi

  if [[ -n "$expected_text" && "$output" != *"$expected_text"* ]]; then
    echo -e "${RED}FAIL${NC} $name: expected text '$expected_text' not found"
    echo "  output: $output"
    ((failed++)) || true
    return
  fi

  echo -e "${GREEN}PASS${NC} $name"
  ((passed++)) || true
}

echo "=== Testing kimi-as-claude.sh wrapper ==="
echo ""

# Content type tests
run_test "array content" "success_array" "Task completed successfully."
run_test "string content" "success_string" "String content from Kimi."
run_test "null content" "success_null" ""
run_test "missing content" "success_no_content" ""
run_test "multi-turn output" "multi_turn" "First response."

# Thinking block tests
run_test "think block hidden by default" "success_with_think" "Done."
run_test "think block shown in verbose" "success_with_think" "Analyzing..." 0 1

# Error handling tests
run_test "error exit 1" "error_exit_1" "kimi exited with code 1" 1
run_test "error exit 75" "error_exit_75" "kimi exited with code 75" 75

# Stderr filtering test
run_test "resume session filtered" "resume_session" "Hello."

# Bad JSON test
run_test "bad json fails" "bad_json" "wrapper translation failed" 1

# Review adapter test
output=$(PATH="$STUB_DIR:$PATH" KIMI_STUB_SCENARIO="echo_prompt" bash "$WRAPPER" <<< "Review this code. <<<RALPHEX:REVIEW_DONE>>>" 2>&1)
if [[ "$output" == *"Ralphex review adapter for Kimi"* ]]; then
  echo -e "${GREEN}PASS${NC} review adapter preamble added"
  ((passed++)) || true
else
  echo -e "${RED}FAIL${NC} review adapter: preamble not found"
  echo "  output: $output"
  ((failed++)) || true
fi

# Verify result event
output=$(PATH="$STUB_DIR:$PATH" KIMI_STUB_SCENARIO="success_array" bash "$WRAPPER" <<< "test" 2>&1)
if [[ "$output" == *'"type":"result","result":""'* ]]; then
  echo -e "${GREEN}PASS${NC} result event emitted on success"
  ((passed++)) || true
else
  echo -e "${RED}FAIL${NC} result event: expected success result event"
  echo "  output: $output"
  ((failed++)) || true
fi

# Verify NO result event on error
output=$(PATH="$STUB_DIR:$PATH" KIMI_STUB_SCENARIO="error_exit_1" bash "$WRAPPER" <<< "test" 2>&1) || true
if [[ "$output" != *'"type":"result","result":""'* ]]; then
  echo -e "${GREEN}PASS${NC} no result event on error"
  ((passed++)) || true
else
  echo -e "${RED}FAIL${NC} result event: should not emit success result on error"
  echo "  output: $output"
  ((failed++)) || true
fi

# Streaming test: wrapper should emit events before EOF
out="/tmp/stream_test_$$.out"

# Use streaming stub with /dev/null stdin; stub outputs first line immediately,
# then sleeps 0.3s before second line. If wrapper is truly streaming,
# the first delta should appear in output well before stub finishes.
PATH="$STUB_DIR:$PATH" KIMI_STUB_SCENARIO="streaming" bash "$WRAPPER" -p "test" </dev/null > "$out" 2>/dev/null &
wrapper_pid=$!

sleep 0.1

# Check output has started before EOF
if grep -q "first" "$out" 2>/dev/null; then
  echo -e "${GREEN}PASS${NC} streaming: events emitted before EOF"
  ((passed++)) || true
else
  echo -e "${RED}FAIL${NC} streaming: wrapper buffered until EOF"
  echo "  output: $(cat "$out" 2>/dev/null || echo '(empty)')"
  ((failed++)) || true
fi

wait "$wrapper_pid" || true

# Verify both lines were received
if ! grep -q "second" "$out" 2>/dev/null; then
  echo -e "${RED}FAIL${NC} streaming: second line missing from output"
  echo "  output: $(cat "$out" 2>/dev/null || echo '(empty)')"
  ((failed++)) || true
fi

rm -f "$out"

echo ""
echo "=== Results: $passed passed, $failed failed ==="

exit $failed
