#!/bin/bash
# Kokoro TTS Hook Installation Script for Claude Code
# This script sets up automatic TTS playback for Claude Code responses

set -e

echo "======================================"
echo "Kokoro TTS Hook Installer"
echo "======================================"
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Check prerequisites
echo "Checking prerequisites..."

# Check for jq
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is not installed${NC}"
    echo "Please install jq first:"
    echo "  Ubuntu/Debian: sudo apt-get install jq"
    echo "  macOS: brew install jq"
    echo "  Fedora: sudo dnf install jq"
    exit 1
fi

# Check for kokoro-tts
if ! command -v kokoro-tts &> /dev/null; then
    echo -e "${RED}Error: kokoro-tts is not installed${NC}"
    echo "Please install kokoro-tts first:"
    echo "  uv tool install kokoro-tts"
    exit 1
fi

echo -e "${GREEN}OK${NC} jq is installed"
echo -e "${GREEN}OK${NC} kokoro-tts is installed"
echo ""

# Check if model files exist in script directory, if not offer to download
if [ ! -f "$SCRIPT_DIR/kokoro-v1.0.onnx" ] || [ ! -f "$SCRIPT_DIR/voices-v1.0.bin" ]; then
    echo -e "${YELLOW}Model files not found in repository${NC}"
    echo ""
    echo "The Kokoro TTS model files (kokoro-v1.0.onnx and voices-v1.0.bin)"
    echo "are required but not present in this directory."
    echo ""
    echo "Would you like to download them now? (335MB total)"
    echo "  1. Yes, download automatically"
    echo "  2. No, I'll download them manually"
    echo ""
    read -rp "Enter choice (1-2) [default: 1]: " download_choice
    download_choice=${download_choice:-1}

    if [ "$download_choice" = "1" ]; then
        echo ""
        echo "Downloading model files from GitHub releases..."

        # Download kokoro-v1.0.onnx
        if [ ! -f "$SCRIPT_DIR/kokoro-v1.0.onnx" ]; then
            echo "Downloading kokoro-v1.0.onnx (310MB)..."
            if command -v curl &> /dev/null; then
                curl -L -o "$SCRIPT_DIR/kokoro-v1.0.onnx" \
                    "https://github.com/thewh1teagle/kokoro-onnx/releases/latest/download/kokoro-v1.0.onnx"
            elif command -v wget &> /dev/null; then
                wget -O "$SCRIPT_DIR/kokoro-v1.0.onnx" \
                    "https://github.com/thewh1teagle/kokoro-onnx/releases/latest/download/kokoro-v1.0.onnx"
            else
                echo -e "${RED}Error: Neither curl nor wget found. Please install one to download files.${NC}"
                exit 1
            fi
        fi

        # Download voices-v1.0.bin
        if [ ! -f "$SCRIPT_DIR/voices-v1.0.bin" ]; then
            echo "Downloading voices-v1.0.bin (25MB)..."
            if command -v curl &> /dev/null; then
                curl -L -o "$SCRIPT_DIR/voices-v1.0.bin" \
                    "https://github.com/thewh1teagle/kokoro-onnx/releases/latest/download/voices-v1.0.bin"
            elif command -v wget &> /dev/null; then
                wget -O "$SCRIPT_DIR/voices-v1.0.bin" \
                    "https://github.com/thewh1teagle/kokoro-onnx/releases/latest/download/voices-v1.0.bin"
            fi
        fi

        echo -e "${GREEN}OK${NC} Model files downloaded"
        echo ""
    else
        echo ""
        echo "Please download the model files manually:"
        echo "  https://github.com/thewh1teagle/kokoro-onnx/releases"
        echo ""
        echo "Place them in: $SCRIPT_DIR/"
        echo "Then run this installer again."
        exit 1
    fi
fi

# Determine where to place model files
echo "Where would you like to store the TTS model files?"
echo "1. Keep in current directory: $SCRIPT_DIR"
echo "2. Move to ~/.local/share/kokoro-tts/"
echo "3. Custom location"
echo ""
read -rp "Enter choice (1-3) [default: 2]: " model_choice
model_choice=${model_choice:-2}

case $model_choice in
    1)
        MODEL_DIR="$SCRIPT_DIR"
        echo "Using current directory: $MODEL_DIR"
        ;;
    2)
        MODEL_DIR="$HOME/.local/share/kokoro-tts"
        mkdir -p "$MODEL_DIR"
        echo "Using: $MODEL_DIR"
        # Copy model files if not already there
        if [ ! -f "$MODEL_DIR/kokoro-v1.0.onnx" ]; then
            echo "Copying kokoro-v1.0.onnx..."
            cp "$SCRIPT_DIR/kokoro-v1.0.onnx" "$MODEL_DIR/"
        fi
        if [ ! -f "$MODEL_DIR/voices-v1.0.bin" ]; then
            echo "Copying voices-v1.0.bin..."
            cp "$SCRIPT_DIR/voices-v1.0.bin" "$MODEL_DIR/"
        fi
        ;;
    3)
        read -rp "Enter custom path: " MODEL_DIR
        MODEL_DIR="${MODEL_DIR/#\~/$HOME}" # Expand tilde
        mkdir -p "$MODEL_DIR"
        # Copy model files
        if [ ! -f "$MODEL_DIR/kokoro-v1.0.onnx" ]; then
            echo "Copying kokoro-v1.0.onnx..."
            cp "$SCRIPT_DIR/kokoro-v1.0.onnx" "$MODEL_DIR/"
        fi
        if [ ! -f "$MODEL_DIR/voices-v1.0.bin" ]; then
            echo "Copying voices-v1.0.bin..."
            cp "$SCRIPT_DIR/voices-v1.0.bin" "$MODEL_DIR/"
        fi
        ;;
esac

echo ""
echo "Model files location: $MODEL_DIR"
echo ""

# Create hooks directory
HOOKS_DIR="$HOME/.claude/hooks"
mkdir -p "$HOOKS_DIR"

# Create tts-stop-hook.sh
echo "Creating TTS playback hook..."
cat > "$HOOKS_DIR/tts-stop-hook.sh" << 'HOOK_EOF'
#!/bin/bash
# Claude Code TTS Hook - Reads Claude's responses using kokoro-tts

# Debug logging
echo "[$(date)] Kokoro TTS hook triggered" >> /tmp/kokoro-hook.log

# Small delay to avoid race condition where transcript isn't fully written yet
sleep 1

# Read the hook input JSON from stdin
input=$(cat)

# Debug: Log the input
echo "[$(date)] Hook input: $input" >> /tmp/kokoro-hook.log

# Extract the transcript path
transcript_path=$(echo "$input" | jq -r '.transcript_path')

# Debug: Log the transcript path
echo "[$(date)] Transcript path: $transcript_path" >> /tmp/kokoro-hook.log

# Expand tilde to home directory if present
transcript_path="${transcript_path/#\~/$HOME}"

# Check if transcript file exists
if [ ! -f "$transcript_path" ]; then
  echo "[$(date)] Transcript file not found: $transcript_path" >> /tmp/kokoro-hook.log
  exit 0
fi

# Extract Claude's last response from the transcript
# Loop through messages in reverse to find text that appears AFTER tool uses completed
# This prevents reading text that PreToolUse hook already played
claude_response=$(tac "$transcript_path" | while IFS= read -r line; do
  message_type=$(echo "$line" | jq -r '.type' 2>/dev/null)

  # Once we see a tool_result, we know tools have been used
  if [ "$message_type" = "tool_result" ]; then
    seen_tool_result=1
  fi

  # Look for assistant text messages
  if [ "$message_type" = "assistant" ]; then
    TEXT=$(echo "$line" | jq -r '.message.content[]? | select(.type == "text") | .text' 2>/dev/null | tr '\n' ' ')

    # Only use text if we haven't seen any tool_results yet (meaning this is final response after tools)
    # OR if we never saw tool_results (meaning no tools were used)
    if [ -n "$TEXT" ]; then
      if [ "$seen_tool_result" != "1" ]; then
        echo "$TEXT"
        break
      fi
    fi
  fi
done | head -c 5000)

# Debug: Log what was extracted
echo "[$(date)] Extracted response: $claude_response" >> /tmp/kokoro-hook.log

# Only proceed if we got a response
if [ -n "$claude_response" ]; then
  echo "[$(date)] Sending to kokoro-tts with af_sky voice" >> /tmp/kokoro-hook.log
  echo "[$(date)] Response length: ${#claude_response}" >> /tmp/kokoro-hook.log

  # Check if response contains TTS_SUMMARY marker
  if echo "$claude_response" | grep -q "<!-- TTS_SUMMARY"; then
    # Extract only the TTS_SUMMARY content
    tts_summary=$(echo "$claude_response" | sed -n 's/.*<!-- TTS_SUMMARY[[:space:]]*\(.*\)[[:space:]]*TTS_SUMMARY -->.*/\1/p')

    if [ -n "$tts_summary" ]; then
      echo "[$(date)] Found TTS_SUMMARY, using summary content only" >> /tmp/kokoro-hook.log
      claude_response="$tts_summary"
    else
      echo "[$(date)] TTS_SUMMARY marker found but empty, falling back to full response" >> /tmp/kokoro-hook.log
    fi
  else
    echo "[$(date)] No TTS_SUMMARY found, using full response with markdown stripping" >> /tmp/kokoro-hook.log

    # Strip markdown formatting using mistune Python library
    # __CLAUDE_TTS_PROJECT_DIR__ is replaced with actual path during installation
    claude_response=$(echo "$claude_response" | uv run --project "__CLAUDE_TTS_PROJECT_DIR__" python scripts/strip_markdown.py 2>/dev/null || echo "$claude_response")
  fi

  echo "[$(date)] Final response for TTS (length: ${#claude_response})" >> /tmp/kokoro-hook.log

  # Save response to temp file to avoid pipe blocking issues
  echo "$claude_response" > /tmp/kokoro-input.txt

  # Run kokoro-tts in a fully detached subshell
  # The subshell pattern (command &) ensures complete detachment
  (kokoro-tts /tmp/kokoro-input.txt --voice af_sky --stream --model "MODEL_PATH_PLACEHOLDER/kokoro-v1.0.onnx" --voices "MODEL_PATH_PLACEHOLDER/voices-v1.0.bin" >>/tmp/kokoro-hook.log 2>&1 &)
else
  echo "[$(date)] No response found" >> /tmp/kokoro-hook.log
fi

# Exit successfully (non-blocking)
exit 0
HOOK_EOF

# Replace placeholders with actual paths
sed -i "s|MODEL_PATH_PLACEHOLDER|$MODEL_DIR|g" "$HOOKS_DIR/tts-stop-hook.sh"
sed -i "s|__CLAUDE_TTS_PROJECT_DIR__|$SCRIPT_DIR|g" "$HOOKS_DIR/tts-stop-hook.sh"

# Create tts-interrupt-hook.sh
echo "Creating TTS interrupt hook..."
cat > "$HOOKS_DIR/tts-interrupt-hook.sh" << 'HOOK_EOF'
#!/bin/bash
# TTS Interrupt Hook - Stops ongoing TTS playback when user submits a new prompt
# This hook is triggered when the user submits a new message to Claude

# Debug logging
echo "[$(date)] TTS Interrupt hook triggered - stopping ongoing TTS playback" >> /tmp/kokoro-hook.log

# Kill all running kokoro-tts processes
pkill -9 kokoro-tts 2>/dev/null

# Log the result
if [ $? -eq 0 ]; then
  echo "[$(date)] Successfully stopped kokoro-tts process" >> /tmp/kokoro-hook.log
else
  echo "[$(date)] No kokoro-tts process was running" >> /tmp/kokoro-hook.log
fi

# Exit successfully (non-blocking)
exit 0
HOOK_EOF

# Create tts-pretooluse-hook.sh
echo "Creating PreToolUse TTS hook..."
cat > "$HOOKS_DIR/tts-pretooluse-hook.sh" << 'HOOK_EOF'
#!/bin/bash
# Claude Code PreToolUse TTS Hook - Reads text that appears before tool uses

# Debug logging
echo "[$(date)] PreToolUse TTS hook triggered" >> /tmp/kokoro-hook.log

# Small delay to allow transcript to be fully written
sleep 0.5

# Read the hook input JSON from stdin
input=$(cat)

# Debug: Log the input
echo "[$(date)] PreToolUse hook input: $input" >> /tmp/kokoro-hook.log

# Extract the transcript path and tool_use_id
transcript_path=$(echo "$input" | jq -r '.transcript_path')
current_tool_use_id=$(echo "$input" | jq -r '.tool_use_id')

echo "[$(date)] Current tool_use_id: $current_tool_use_id" >> /tmp/kokoro-hook.log

# Expand tilde to home directory if present
transcript_path="${transcript_path/#\~/$HOME}"

# Check if transcript file exists
if [ ! -f "$transcript_path" ]; then
  echo "[$(date)] Transcript file not found: $transcript_path" >> /tmp/kokoro-hook.log
  exit 0
fi

# Check if this is the first tool_use in the current message
# Extract the first tool_use_id from the last assistant message
first_tool_use_id=$(tac "$transcript_path" | while IFS= read -r line; do
  if echo "$line" | jq -e '.type == "assistant"' >/dev/null 2>&1; then
    echo "$line" | jq -r '.message.content[] | select(.type == "tool_use") | .id' 2>/dev/null | head -1
    break
  fi
done)

echo "[$(date)] First tool_use_id in message: $first_tool_use_id" >> /tmp/kokoro-hook.log

# Only proceed if this is the first tool use
if [ "$current_tool_use_id" != "$first_tool_use_id" ]; then
  echo "[$(date)] Skipping - not the first tool use in this message" >> /tmp/kokoro-hook.log
  exit 0
fi

echo "[$(date)] This is the first tool use - proceeding with TTS" >> /tmp/kokoro-hook.log

# Extract text from assistant messages that appear before the tool use
# Claude Code splits responses into separate messages for text and tool_use blocks
# We need to find text from the most recent assistant text message before the first tool use
claude_response=$(tac "$transcript_path" | while IFS= read -r line; do
  if echo "$line" | jq -e '.type == "assistant"' >/dev/null 2>&1; then
    # Check if this message contains the current tool_use_id
    tool_ids=$(echo "$line" | jq -r '.message.content[] | select(.type == "tool_use") | .id' 2>/dev/null)

    # If we found the message with the first tool use, now look for preceding text
    if echo "$tool_ids" | grep -q "$current_tool_use_id"; then
      echo "[$(date)] Found message containing current tool_use_id" >> /tmp/kokoro-hook.log
      # Mark that we've found the tool use message, now collect text from previous messages
      found_tool_use=1
      continue
    fi

    # If we've found the tool use and this is a text message, extract it
    if [ "$found_tool_use" = "1" ]; then
      content_type=$(echo "$line" | jq -r '.message.content[0].type' 2>/dev/null)
      if [ "$content_type" = "text" ]; then
        TEXT=$(echo "$line" | jq -r '.message.content[] | select(.type == "text") | .text' 2>/dev/null)
        if [ -n "$TEXT" ]; then
          echo "[$(date)] Found text message before tool use" >> /tmp/kokoro-hook.log
          echo "$TEXT"
          break
        fi
      fi
    fi
  fi
done | head -c 5000)

# Debug: Log what was extracted
echo "[$(date)] PreToolUse extracted text: $claude_response" >> /tmp/kokoro-hook.log

# Check if response contains TTS_SUMMARY marker
# If it does, skip playback - let the Stop hook handle TTS_SUMMARY extraction
if echo "$claude_response" | grep -q "<!-- TTS_SUMMARY"; then
  echo "[$(date)] Skipping - message contains TTS_SUMMARY, let Stop hook handle it" >> /tmp/kokoro-hook.log
  exit 0
fi

# Session-based deduplication: compute hash of the text
# Hash files are cleared only at SessionEnd, so deduplication lasts entire session
text_hash=$(echo "$claude_response" | md5sum | awk '{print $1}')
last_hash_file="/tmp/kokoro-pretool-last-hash.txt"
last_hash=$(cat "$last_hash_file" 2>/dev/null)

# If we played this exact text in this session, skip (no time limit)
if [ "$text_hash" = "$last_hash" ]; then
  echo "[$(date)] Skipping - same text already played in this session" >> /tmp/kokoro-hook.log
  exit 0
fi

# Only proceed if we got a response and it's not empty
if [ -n "$claude_response" ] && [ ${#claude_response} -gt 10 ]; then
  echo "[$(date)] Sending to kokoro-tts with af_sky voice" >> /tmp/kokoro-hook.log
  echo "[$(date)] Response length: ${#claude_response}" >> /tmp/kokoro-hook.log

  # Strip markdown formatting using mistune Python library
  # __CLAUDE_TTS_PROJECT_DIR__ is replaced with actual path during installation
  claude_response=$(echo "$claude_response" | uv run --project "__CLAUDE_TTS_PROJECT_DIR__" python scripts/strip_markdown.py 2>/dev/null || echo "$claude_response")

  echo "[$(date)] Response after markdown strip (length: ${#claude_response})" >> /tmp/kokoro-hook.log

  # Save the hash for session-based deduplication
  echo "$text_hash" > "$last_hash_file"
  echo "[$(date)] Saved text hash for session-based deduplication: $text_hash" >> /tmp/kokoro-hook.log

  # Save response to temp file
  echo "$claude_response" > /tmp/kokoro-pretool-input.txt

  # Run kokoro-tts in a fully detached subshell
  (kokoro-tts /tmp/kokoro-pretool-input.txt --voice af_sky --stream --model "MODEL_PATH_PLACEHOLDER/kokoro-v1.0.onnx" --voices "MODEL_PATH_PLACEHOLDER/voices-v1.0.bin" >>/tmp/kokoro-hook.log 2>&1 &)
else
  echo "[$(date)] No text before tool uses, or text too short (${#claude_response} chars)" >> /tmp/kokoro-hook.log
fi

# Exit successfully (non-blocking)
exit 0
HOOK_EOF

# Replace placeholders with actual paths
sed -i "s|MODEL_PATH_PLACEHOLDER|$MODEL_DIR|g" "$HOOKS_DIR/tts-pretooluse-hook.sh"
sed -i "s|__CLAUDE_TTS_PROJECT_DIR__|$SCRIPT_DIR|g" "$HOOKS_DIR/tts-pretooluse-hook.sh"

# Create tts-session-end-hook.sh
echo "Creating SessionEnd TTS hook..."
cat > "$HOOKS_DIR/tts-session-end-hook.sh" << 'HOOK_EOF'
#!/bin/bash
# Claude Code SessionEnd Hook - Cleanup TTS processes and temporary files
# This hook is triggered when a Claude Code session ends

# Read hook input
input=$(cat)

# Extract session information
session_id=$(echo "$input" | jq -r '.session_id')
reason=$(echo "$input" | jq -r '.reason')

# Log session end
echo "[$(date)] SessionEnd hook triggered for session $session_id (reason: $reason)" >> /tmp/kokoro-hook.log

# Kill any running kokoro-tts processes
pkill -9 kokoro-tts 2>/dev/null
if [ $? -eq 0 ]; then
  echo "[$(date)] Killed running kokoro-tts processes" >> /tmp/kokoro-hook.log
fi

# Clean up TTS temporary files
rm -f /tmp/kokoro-input.txt /tmp/kokoro-pretool-input.txt 2>/dev/null

# Clean up hash tracking files for fresh start in next session
rm -f /tmp/kokoro-pretool-last-hash.txt /tmp/kokoro-pretool-last-time.txt 2>/dev/null

echo "[$(date)] Session cleanup completed for session $session_id" >> /tmp/kokoro-hook.log

# Exit successfully
exit 0
HOOK_EOF

# Make hooks executable
chmod +x "$HOOKS_DIR/tts-stop-hook.sh"
chmod +x "$HOOKS_DIR/tts-interrupt-hook.sh"
chmod +x "$HOOKS_DIR/tts-pretooluse-hook.sh"
chmod +x "$HOOKS_DIR/tts-session-end-hook.sh"

echo -e "${GREEN}OK${NC} Hook scripts created and made executable"
echo ""

# Configure ~/.claude/settings.json
SETTINGS_FILE="$HOME/.claude/settings.json"

echo "Configuring Claude Code settings..."

# Create or update settings.json
if [ ! -f "$SETTINGS_FILE" ]; then
    # Create new settings file
    cat > "$SETTINGS_FILE" << 'SETTINGS_EOF'
{
  "env": {
    "KOKORO_VOICE": "af_sky"
  },
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/tts-interrupt-hook.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/tts-pretooluse-hook.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/tts-stop-hook.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/tts-session-end-hook.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
SETTINGS_EOF
    echo -e "${GREEN}OK${NC} Created new settings.json with KOKORO_VOICE=af_sky"
else
    # Backup existing settings
    cp "$SETTINGS_FILE" "$SETTINGS_FILE.backup"
    echo "Backed up existing settings to $SETTINGS_FILE.backup"

    # Merge hooks into existing settings and add KOKORO_VOICE if not present
    jq '.hooks.UserPromptSubmit = [{"hooks": [{"type": "command", "command": "bash ~/.claude/hooks/tts-interrupt-hook.sh", "timeout": 5}]}] |
        .hooks.PreToolUse = [{"hooks": [{"type": "command", "command": "bash ~/.claude/hooks/tts-pretooluse-hook.sh", "timeout": 5}]}] |
        .hooks.Stop = [{"hooks": [{"type": "command", "command": "bash ~/.claude/hooks/tts-stop-hook.sh", "timeout": 10}]}] |
        .hooks.SessionEnd = [{"hooks": [{"type": "command", "command": "bash ~/.claude/hooks/tts-session-end-hook.sh", "timeout": 5}]}] |
        .env.KOKORO_VOICE //= "af_sky"' \
        "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"

    echo -e "${GREEN}OK${NC} Updated existing settings.json with TTS hooks and KOKORO_VOICE"
fi

echo ""

# Configure ~/.claude/CLAUDE.md with TTS instructions
CLAUDE_MD="$HOME/.claude/CLAUDE.md"

echo "Configuring TTS summary instructions in CLAUDE.md..."

# Check if CLAUDE.md already has TTS_SUMMARY configuration
if [ -f "$CLAUDE_MD" ] && grep -q "TTS_SUMMARY" "$CLAUDE_MD"; then
    echo "TTS instructions already present in CLAUDE.md"
else
    # Create the file if it doesn't exist or append if it does
    if [ ! -f "$CLAUDE_MD" ]; then
        echo "Creating $CLAUDE_MD with TTS instructions..."
        cat > "$CLAUDE_MD" << 'CLAUDE_EOF'
# Global Claude Code Instructions

## TTS Summary Instructions

At the END of EVERY response, include a TTS-friendly summary in the following format:

<!-- TTS_SUMMARY
Brief, natural language summary of what you did. No URLs, no technical jargon, no code snippets.
Just explain in 1-2 sentences what was accomplished, like you're talking to someone.
TTS_SUMMARY -->

Keep the summary conversational and avoid:
- URLs (say "a link" instead)
- File paths (say "the configuration file" instead)
- Technical constants or variable names
- Code syntax

The technical response should come BEFORE this summary.

## Output Format

- Only output plain ASCII text in your responses.
CLAUDE_EOF
        echo -e "${GREEN}OK${NC} Created CLAUDE.md with TTS instructions"
    else
        echo "Appending TTS instructions to existing CLAUDE.md..."
        cat >> "$CLAUDE_MD" << 'CLAUDE_EOF'

## TTS Summary Instructions

At the END of EVERY response, include a TTS-friendly summary in the following format:

<!-- TTS_SUMMARY
Brief, natural language summary of what you did. No URLs, no technical jargon, no code snippets.
Just explain in 1-2 sentences what was accomplished, like you're talking to someone.
TTS_SUMMARY -->

Keep the summary conversational and avoid:
- URLs (say "a link" instead)
- File paths (say "the configuration file" instead)
- Technical constants or variable names
- Code syntax

The technical response should come BEFORE this summary.
CLAUDE_EOF
        echo -e "${GREEN}OK${NC} Appended TTS instructions to existing CLAUDE.md"
    fi
fi

echo ""
echo "======================================"
echo -e "${GREEN}Installation Complete!${NC}"
echo "======================================"
echo ""
echo "The following hooks have been installed:"
echo "  - Stop hook (TTS playback): ~/.claude/hooks/tts-stop-hook.sh"
echo "  - PreToolUse hook (TTS narration): ~/.claude/hooks/tts-pretooluse-hook.sh"
echo "  - UserPromptSubmit hook (TTS interrupt): ~/.claude/hooks/tts-interrupt-hook.sh"
echo "  - SessionEnd hook (Cleanup): ~/.claude/hooks/tts-session-end-hook.sh"
echo ""
echo "Model files location: $MODEL_DIR"
echo ""
echo "Next steps:"
echo "  1. Start or restart Claude Code"
echo "  2. Claude's responses will be automatically read aloud"
echo "  3. Submit a new message to interrupt ongoing TTS playback"
echo ""
echo "To verify installation:"
echo "  - Run '/hooks' in Claude Code to see registered hooks"
echo "  - Check logs: tail -f /tmp/kokoro-hook.log"
echo ""
echo "To customize the voice, edit:"
echo "  ~/.claude/hooks/tts-stop-hook.sh"
echo "  (change --voice af_sky to another voice)"
echo ""
echo "For troubleshooting, see: docs/TTS_HOOK_DOCUMENTATION.md"
echo ""
