#!/usr/bin/env bash
# kimi-as-claude.sh - wraps Kimi CLI to produce Claude-compatible stream-json output.
#
# This script translates Kimi JSONL events into the Claude stream-json format
# that ralphex's ClaudeExecutor can parse, allowing Kimi CLI to be used as a
# drop-in replacement for Claude Code in task and review phases.
#
# Config example (~/.config/ralphex/config or .ralphex/config):
#   claude_command = /path/to/kimi-as-claude.sh
#   claude_args =
#
# Environment variables:
#   KIMI_MODEL - Kimi model to use (default: kimi default)
#   KIMI_VERBOSE - set to 1 to include thinking blocks in output (default: 0)

set -euo pipefail

# verify jq is available (required for JSON translation)
command -v jq >/dev/null 2>&1 || { echo "error: jq is required but not found" >&2; exit 1; }

# ralphex passes prompt via stdin (primary path, avoids Windows 8191-char cmd limit).
# also accept -p flag for backward compatibility with direct invocations.
# all other flags are ignored gracefully (--dangerously-skip-permissions, etc.)
prompt=""
model=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p) prompt="${2:-}"; shift; shift 2>/dev/null || true ;;
    --model) model="${2:-}"; shift; shift 2>/dev/null || true ;;
    --effort) shift 2>/dev/null || true ;; # kimi does not support effort levels
    --dangerously-skip-permissions|--output-format|--verbose) shift ;;
    *) shift ;; # ignore unknown flags
  esac
done

if [[ -z "$prompt" ]]; then
  # fall back to stdin: ralphex passes prompt via pipe
  if [[ ! -t 0 ]]; then
    prompt=$(cat)
  fi
fi

if [[ -z "$prompt" ]]; then
  echo "error: no prompt provided (expected -p flag or stdin)" >&2
  exit 1
fi

# review-phase adaptation
# ralphex review prompts contain Claude Task-tool instructions.
# Kimi uses native agent capabilities, so we prepend an adapter preamble.
if [[ "$prompt" == *'<<<RALPHEX:REVIEW_DONE>>>'* ]]; then
  adapter_text=$'Ralphex review adapter for Kimi:\n- Interpret review "Task tool" instructions using Kimi native agent capabilities.\n- Launch all requested review agents in parallel when possible.\n- Wait for all review agents before collecting findings and applying fixes.\n- Keep original review workflow and all <<<RALPHEX:...>>> signals unchanged.'
  prompt="$adapter_text"$'\n\n'"$prompt"
fi

# configurable via environment
KIMI_MODEL="${KIMI_MODEL:-$model}"
KIMI_VERBOSE="${KIMI_VERBOSE:-0}"
if [[ "$KIMI_VERBOSE" != "0" && "$KIMI_VERBOSE" != "1" ]]; then
  echo "warning: KIMI_VERBOSE must be 0 or 1, got '$KIMI_VERBOSE', defaulting to 0" >&2
  KIMI_VERBOSE=0
fi

# build kimi arguments
kimi_args=(--print --output-format stream-json --yolo)
[[ -n "$KIMI_MODEL" ]] && kimi_args+=(-m "$KIMI_MODEL")

# run kimi with JSON output, translate events to claude stream-json format.
# stdout is streamed in real-time through the pipe.
# stderr is captured for post-processing.
# exit code is saved via a side-channel file to survive the pipe.
kimi_err="$(mktemp)"
kimi_exit_file="$(mktemp)"
trap 'rm -f "$kimi_err" "$kimi_exit_file"' EXIT

set +o pipefail
set +e
{
  printf '%s' "$prompt" | kimi "${kimi_args[@]}" 2> "$kimi_err"
  echo "$?" > "$kimi_exit_file"
} | while IFS= read -r line; do
  set -e

  # skip non-JSON lines
  [[ "$line" =~ ^\{ ]] || continue

  # determine .content type and emit appropriate events
  content_type=$(echo "$line" | jq -r '(.content | type) // "null"')

  case "$content_type" in
    array)
      echo "$line" | jq -c --argjson verbose "$KIMI_VERBOSE" '
        if .role == "assistant" then
          (.content // [])[] |
          if .type == "text" then
            {type: "content_block_delta", delta: {type: "text_delta", text: .text}}
          elif .type == "think" and $verbose == 1 then
            {type: "content_block_delta", delta: {type: "text_delta", text: ("> Thinking:\n" + .think + "\n\n")}}
          else empty
          end
        else
          empty
        end
      '
      ;;
    string)
      echo "$line" | jq -c '
        if .role == "assistant" and (.content // "") != "" then
          {type: "content_block_delta", delta: {type: "text_delta", text: .content}}
        else
          empty
        end
      '
      ;;
    *)
      # null or unknown type — skip
      ;;
  esac
done
while_exit=$?
set -e
set -o pipefail

kimi_exit=$(cat "$kimi_exit_file")

# filter known harmless stderr lines; pass through the rest
if [[ -s "$kimi_err" ]]; then
  filtered_err=$(grep -v "To resume this session" "$kimi_err" || true)
  if [[ -n "$filtered_err" ]]; then
    echo "$filtered_err" >&2
  fi
fi

# if translation failed, propagate the error
if [[ "$while_exit" -ne 0 ]]; then
  echo "error: wrapper translation failed (exit $while_exit)" >&2
  exit 1
fi

# if kimi failed, propagate the error and do not emit a success result
if [[ "$kimi_exit" -ne 0 ]]; then
  echo "error: kimi exited with code $kimi_exit" >&2
  exit "$kimi_exit"
fi

# emit result only on success
echo '{"type":"result","result":""}'
