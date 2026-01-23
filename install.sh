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

# Cross-platform sed in-place editing
# macOS uses BSD sed which requires -i '' whereas GNU sed uses -i without argument
sed_in_place() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

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

# Create tts-stop-hook.sh by copying from hooks/ directory (single source of truth)
echo "Creating TTS playback hook..."
cp "$SCRIPT_DIR/hooks/tts-stop-hook.sh" "$HOOKS_DIR/tts-stop-hook.sh"

# Replace placeholders with actual paths
sed_in_place "s|MODEL_PATH_PLACEHOLDER|$MODEL_DIR|g" "$HOOKS_DIR/tts-stop-hook.sh"
sed_in_place "s|__CLAUDE_TTS_PROJECT_DIR__|$SCRIPT_DIR|g" "$HOOKS_DIR/tts-stop-hook.sh"

# Create tts-interrupt-hook.sh by copying from hooks/ directory (single source of truth)
echo "Creating TTS interrupt hook..."
cp "$SCRIPT_DIR/hooks/tts-interrupt-hook.sh" "$HOOKS_DIR/tts-interrupt-hook.sh"

# Replace placeholders with actual paths
sed_in_place "s|__CLAUDE_TTS_PROJECT_DIR__|$SCRIPT_DIR|g" "$HOOKS_DIR/tts-interrupt-hook.sh"

# Create tts-pretooluse-hook.sh by copying from hooks/ directory (single source of truth)
echo "Creating PreToolUse TTS hook..."
cp "$SCRIPT_DIR/hooks/tts-pretooluse-hook.sh" "$HOOKS_DIR/tts-pretooluse-hook.sh"

# Replace placeholders with actual paths
sed_in_place "s|MODEL_PATH_PLACEHOLDER|$MODEL_DIR|g" "$HOOKS_DIR/tts-pretooluse-hook.sh"
sed_in_place "s|__CLAUDE_TTS_PROJECT_DIR__|$SCRIPT_DIR|g" "$HOOKS_DIR/tts-pretooluse-hook.sh"

# Create tts-session-end-hook.sh by copying from hooks/ directory (single source of truth)
echo "Creating SessionEnd TTS hook..."
cp "$SCRIPT_DIR/hooks/tts-session-end-hook.sh" "$HOOKS_DIR/tts-session-end-hook.sh"

# Make hooks executable
chmod +x "$HOOKS_DIR/tts-stop-hook.sh"
chmod +x "$HOOKS_DIR/tts-interrupt-hook.sh"
chmod +x "$HOOKS_DIR/tts-pretooluse-hook.sh"
chmod +x "$HOOKS_DIR/tts-session-end-hook.sh"

# Make audio ducking script executable
chmod +x "$SCRIPT_DIR/scripts/audio-duck.sh"

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
