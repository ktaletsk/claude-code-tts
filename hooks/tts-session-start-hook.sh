#!/usr/bin/env bash
# SessionStart hook: injects tts-session-start-context.md (the TTS_SUMMARY
# instructions) into every new session's context, so they don't have to live
# in ~/.claude/CLAUDE.md. Edit the .md file to change what gets injected.

set -euo pipefail

CONTEXT_FILE="${HOME}/.claude/hooks/tts-session-start-context.md"

# Nothing to inject is not an error - stay silent so the session starts clean.
[ -f "$CONTEXT_FILE" ] || exit 0

# jq -Rs slurps the file as one raw string and emits it JSON-escaped.
jq -Rs '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: .}}' "$CONTEXT_FILE"
