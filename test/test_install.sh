#!/usr/bin/env bash
# Tests for install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALLER="$PROJECT_DIR/install.sh"
WRAPPER_SRC="$PROJECT_DIR/kimi-as-claude.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

passed=0
failed=0

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  local name="$3"
  if grep -q "$pattern" "$file" 2>/dev/null; then
    echo -e "${GREEN}PASS${NC} $name"
    ((passed++)) || true
  else
    echo -e "${RED}FAIL${NC} $name: pattern '$pattern' not found in $file"
    ((failed++)) || true
  fi
}

assert_file_not_contains() {
  local file="$1"
  local pattern="$2"
  local name="$3"
  if ! grep -q "$pattern" "$file" 2>/dev/null; then
    echo -e "${GREEN}PASS${NC} $name"
    ((passed++)) || true
  else
    echo -e "${RED}FAIL${NC} $name: pattern '$pattern' should not be in $file"
    ((failed++)) || true
  fi
}

assert_file_not_exists() {
  local file="$1"
  local name="$2"
  if [[ ! -e "$file" ]]; then
    echo -e "${GREEN}PASS${NC} $name"
    ((passed++)) || true
  else
    echo -e "${RED}FAIL${NC} $name: file $file should not exist"
    ((failed++)) || true
  fi
}

assert_file_exists() {
  local file="$1"
  local name="$2"
  if [[ -e "$file" ]]; then
    echo -e "${GREEN}PASS${NC} $name"
    ((passed++)) || true
  else
    echo -e "${RED}FAIL${NC} $name: file $file should exist"
    ((failed++)) || true
  fi
}

echo "=== Testing install.sh ==="
echo ""

# Test 1: Install kimi on project with existing config
case_dir=$(mktemp -d)
mkdir -p "$case_dir/.ralphex"
echo "# existing config" > "$case_dir/.ralphex/config"
cd "$case_dir" && bash "$INSTALLER" kimi >/dev/null 2>&1
assert_file_exists "$case_dir/.ralphex/scripts/kimi-as-claude.sh" "wrapper installed"
assert_file_contains "$case_dir/.ralphex/config" "claude_command = .ralphex/scripts/kimi-as-claude.sh" "config updated with claude_command"
assert_file_contains "$case_dir/.ralphex/config" "claude_args =" "config updated with claude_args"
assert_file_exists "$case_dir/.ralphex/config.backup" "backup created"
rm -rf "$case_dir"

# Test 2: Install kimi on project with sparse config (no claude_command/claude_args)
case_dir=$(mktemp -d)
mkdir -p "$case_dir/.ralphex"
echo "codex_enabled = false" > "$case_dir/.ralphex/config"
cd "$case_dir" && bash "$INSTALLER" kimi >/dev/null 2>&1
assert_file_contains "$case_dir/.ralphex/config" "claude_command = .ralphex/scripts/kimi-as-claude.sh" "sparse config: claude_command added"
assert_file_contains "$case_dir/.ralphex/config" "claude_args =" "sparse config: claude_args added"
rm -rf "$case_dir"

# Test 3: Restore original from backup
case_dir=$(mktemp -d)
mkdir -p "$case_dir/.ralphex"
echo "original config" > "$case_dir/.ralphex/config"
cd "$case_dir" && bash "$INSTALLER" kimi >/dev/null 2>&1
assert_file_exists "$case_dir/.ralphex/scripts/kimi-as-claude.sh" "pre-restore: wrapper exists"
cd "$case_dir" && bash "$INSTALLER" original >/dev/null 2>&1
assert_file_not_exists "$case_dir/.ralphex/scripts/kimi-as-claude.sh" "restore: wrapper removed"
assert_file_contains "$case_dir/.ralphex/config" "original config" "restore: config restored"
assert_file_not_exists "$case_dir/.ralphex/config.backup" "restore: backup removed"
rm -rf "$case_dir"

# Test 4: Restore when no backup exists but wrapper was manually placed (should fail, not delete config)
case_dir=$(mktemp -d)
mkdir -p "$case_dir/.ralphex/scripts"
cp "$WRAPPER_SRC" "$case_dir/.ralphex/scripts/kimi-as-claude.sh"
echo "important = keep-me" > "$case_dir/.ralphex/config"
exit_code=0
cd "$case_dir" && bash "$INSTALLER" original >/dev/null 2>&1 || exit_code=$?
if [[ "$exit_code" -ne 0 ]]; then
  echo -e "${GREEN}PASS${NC} restore without backup/sentinel: exits with error"
  ((passed++)) || true
else
  echo -e "${RED}FAIL${NC} restore without backup/sentinel: should exit with error"
  ((failed++)) || true
fi
assert_file_exists "$case_dir/.ralphex/config" "restore without backup: config preserved"
rm -rf "$case_dir"

# Test 5: Restore when install created config from scratch (sentinel exists) — config unchanged
case_dir=$(mktemp -d)
mkdir -p "$case_dir/.ralphex"
cd "$case_dir" && bash "$INSTALLER" kimi >/dev/null 2>&1
assert_file_exists "$case_dir/.ralphex/.kimi-no-original-config" "sentinel created"
cd "$case_dir" && bash "$INSTALLER" original >/dev/null 2>&1
assert_file_not_exists "$case_dir/.ralphex/config" "restore with sentinel: config removed"
assert_file_not_exists "$case_dir/.ralphex/.kimi-no-original-config" "restore with sentinel: sentinel removed"
rm -rf "$case_dir"

# Test 6: Restore when install created config, user added settings — preserve user settings
case_dir=$(mktemp -d)
mkdir -p "$case_dir/.ralphex"
cd "$case_dir" && bash "$INSTALLER" kimi >/dev/null 2>&1
echo "# user customization after install" >> "$case_dir/.ralphex/config"
cd "$case_dir" && bash "$INSTALLER" original >/dev/null 2>&1
assert_file_exists "$case_dir/.ralphex/config" "restore sentinel with user settings: config preserved"
assert_file_contains "$case_dir/.ralphex/config" "user customization after install" "restore sentinel: user settings kept"
assert_file_not_contains "$case_dir/.ralphex/config" "claude_command" "restore sentinel: claude_command removed"
assert_file_not_exists "$case_dir/.ralphex/.kimi-no-original-config" "restore sentinel: sentinel removed"
rm -rf "$case_dir"

# Test 7: Install when .ralphex exists but no config
case_dir=$(mktemp -d)
mkdir -p "$case_dir/.ralphex"
cd "$case_dir" && bash "$INSTALLER" kimi >/dev/null 2>&1
assert_file_exists "$case_dir/.ralphex/config" "no-config install: config created"
assert_file_contains "$case_dir/.ralphex/config" "claude_command = .ralphex/scripts/kimi-as-claude.sh" "no-config install: claude_command set"
rm -rf "$case_dir"

# Test 8: Install in a project with no .ralphex at all (auto-create)
case_dir=$(mktemp -d)
cd "$case_dir" && bash "$INSTALLER" kimi >/dev/null 2>&1
assert_file_exists "$case_dir/.ralphex/config" "auto-create: config created"
assert_file_exists "$case_dir/.ralphex/scripts/kimi-as-claude.sh" "auto-create: wrapper installed"
rm -rf "$case_dir"

# Test 9: Double install + original for sentinel scenario (should not create broken backup)
case_dir=$(mktemp -d)
mkdir -p "$case_dir/.ralphex"
cd "$case_dir" && bash "$INSTALLER" kimi >/dev/null 2>&1
assert_file_exists "$case_dir/.ralphex/.kimi-no-original-config" "double-install: sentinel exists after first"
cd "$case_dir" && bash "$INSTALLER" kimi >/dev/null 2>&1
assert_file_not_exists "$case_dir/.ralphex/config.backup" "double-install: no backup created on second install"
cd "$case_dir" && bash "$INSTALLER" original >/dev/null 2>&1
assert_file_not_exists "$case_dir/.ralphex/config" "double-install original: config removed"
assert_file_not_exists "$case_dir/.ralphex/.kimi-no-original-config" "double-install original: sentinel removed"
assert_file_not_exists "$case_dir/.ralphex/scripts/kimi-as-claude.sh" "double-install original: wrapper removed"
rm -rf "$case_dir"

echo ""
echo "=== Results: $passed passed, $failed failed ==="

exit $failed
