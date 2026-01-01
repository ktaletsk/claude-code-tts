# Kokoro TTS Hook for Claude Code

Automatic TTS (text-to-speech) integration for Claude Code using the [Kokoro TTS model](https://github.com/nazdridoy/kokoro-tts). This project provides voice feedback that reads Claude's responses aloud as you work.

## Features

- **Automatic TTS Playback**: Claude's responses are automatically read aloud using Kokoro TTS
- **Smart Interruption**: Audio stops automatically when you submit a new message
- **Non-Blocking**: Audio plays in the background without interfering with your workflow
- **Clean Speech**: Automatically strips markdown and technical formatting for clear audio
- **TTS Summary Mode**: Optional summary extraction for concise audio feedback

## What's Included

This repository contains:

- `install.sh` - Automated installation script for setting up hooks
- `hooks/` - Reference copies of the TTS hook scripts
- `docs/TTS_HOOK_DOCUMENTATION.md` - Comprehensive documentation and troubleshooting guide
- `CLAUDE.md` - Repository context for Claude Code

Note: Model files are excluded. When you run `./install.sh`, it will automatically download them from the [kokoro-onnx GitHub releases](https://github.com/thewh1teagle/kokoro-onnx/releases) if they're not present.

## Prerequisites

- **Claude Code** - Get it from [claude.ai/code](https://claude.ai/code)
- **uv** - Fast Python package installer (get it from [astral.sh/uv](https://astral.sh))
- **kokoro-tts CLI** - Will be installed via uv
- **jq** - JSON processor (usually pre-installed on Linux/Mac)
- **curl or wget** - For downloading model files (usually pre-installed)

### Installing kokoro-tts

```bash
# Install using uv (recommended)
uv tool install kokoro-tts

# Verify installation
kokoro-tts --help
```

## Quick Start

1. **Clone this repository**:

   ```bash
   git clone <repository-url>
   cd claude-code-tts
   ```

2. **Run the installer**:

   ```bash
   ./install.sh
   ```

   The installer will:
   - Check for required dependencies
   - Download model files if not present
   - Set up TTS hooks in `~/.claude/hooks/`
   - Configure Claude Code settings
   - Add TTS summary instructions to `~/.claude/CLAUDE.md` (preserves existing content)

3. **Start using Claude Code**:
   The TTS system will automatically activate and read responses aloud.

## How It Works

The system uses Claude Code's hook system to automatically:

1. **Capture responses**: When Claude finishes responding, a Stop event triggers
2. **Extract text**: The hook extracts Claude's text from the conversation transcript
3. **Process for TTS**: Strips markdown formatting and technical elements
4. **Play audio**: Streams to kokoro-tts with the af_sky voice
5. **Handle interruptions**: Kills TTS playback when you submit a new prompt

## Configuration

### Hook Location

After installation, hooks are located at:
- `~/.claude/hooks/tts-stop-hook.sh` - Main TTS playback hook (Stop event)
- `~/.claude/hooks/tts-pretooluse-hook.sh` - Pre-tool narration (PreToolUse event)
- `~/.claude/hooks/tts-interrupt-hook.sh` - Interruption handler (UserPromptSubmit event)
- `~/.claude/hooks/tts-session-end-hook.sh` - Session cleanup (SessionEnd event)

### Changing Voice

Set the `KOKORO_VOICE` environment variable in `~/.claude/settings.json`:

```json
{
  "env": {
    "KOKORO_VOICE": "af_bella"
  }
}
```

The default voice is `af_sky`. Changes take effect on the next Claude Code session.

#### Available Voices (54 total)

**American English:**

- Female: `af_alloy`, `af_aoede`, `af_bella`, `af_heart`, `af_jessica`, `af_kore`, `af_nicole`, `af_nova`, `af_river`, `af_sarah`, `af_sky`
- Male: `am_adam`, `am_echo`, `am_eric`, `am_fenrir`, `am_liam`, `am_michael`, `am_onyx`, `am_puck`

**British English:**

- Female: `bf_alice`, `bf_emma`, `bf_isabella`, `bf_lily`
- Male: `bm_daniel`, `bm_fable`, `bm_george`, `bm_lewis`

**Other Languages:**

- French: `ff_siwis`
- Italian: `if_sara`, `im_nicola`
- Japanese: `jf_alpha`, `jf_gongitsune`, `jf_nezumi`, `jf_tebukuro`, `jm_kumo`
- Mandarin: `zf_xiaobei`, `zf_xiaoni`, `zf_xiaoxiao`, `zf_xiaoyi`, `zm_yunjian`, `zm_yunxi`, `zm_yunxia`, `zm_yunyang`

See [Kokoro VOICES.md](https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md) for the complete list

### TTS Summary Mode

The installer automatically adds TTS summary instructions to `~/.claude/CLAUDE.md`. This enables Claude to provide concise, spoken summaries at the end of each response.

The configuration tells Claude to include a special TTS-friendly summary:

```markdown
<!-- TTS_SUMMARY
Brief, natural language summary of what you did. No URLs, no technical jargon.
TTS_SUMMARY -->
```

The hook automatically detects and reads only the summary portion, providing shorter and more focused audio feedback.

## Troubleshooting

### No audio playing?

1. Check if kokoro-tts is installed: `kokoro-tts --help`
2. Check hook logs: `tail -f /tmp/kokoro-hook.log`
3. Verify hooks are executable: `ls -l ~/.claude/hooks/`

### Audio cuts off mid-sentence?

Increase the character limit in the hook (default: 5000 characters):

```bash
# In tts-stop-hook.sh
' | head -c 10000)  # Increased to 10000
```

### Audio continues after interruption?

Check that the interrupt hook is properly installed:

```bash
cat ~/.claude/hooks/tts-interrupt-hook.sh
```

### Detailed Troubleshooting

See `docs/TTS_HOOK_DOCUMENTATION.md` for comprehensive troubleshooting steps.

## Manual Installation

If you prefer manual setup instead of using `install.sh`:

1. **Copy model files**:

   ```bash
   # Models can stay in this directory or be moved elsewhere
   # The hooks don't need to reference them directly
   ```

2. **Create hook directory**:

   ```bash
   mkdir -p ~/.claude/hooks
   ```

3. **Create TTS hook** (`~/.claude/hooks/tts-stop-hook.sh`):
   See `docs/TTS_HOOK_DOCUMENTATION.md` for the full hook script.

4. **Create interrupt hook** (`~/.claude/hooks/tts-interrupt-hook.sh`):
   See `docs/TTS_HOOK_DOCUMENTATION.md` for the full hook script.

5. **Make hooks executable**:

   ```bash
   chmod +x ~/.claude/hooks/tts-stop-hook.sh
   chmod +x ~/.claude/hooks/tts-interrupt-hook.sh
   ```

6. **Configure hooks in `~/.claude/settings.json`**:

   ```json
   {
     "hooks": {
       "Stop": [{"hooks": [{"type": "command", "command": "bash ~/.claude/hooks/tts-stop-hook.sh", "timeout": 10}]}],
       "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "bash ~/.claude/hooks/tts-interrupt-hook.sh", "timeout": 5}]}]
     }
   }
   ```

## Project Structure

```text
claude-code-tts/
├── README.md                      # This file
├── LICENSE                        # MIT License
├── install.sh                     # Automated setup script
├── CLAUDE.md                      # Repository context for Claude Code
├── pyproject.toml                 # Python project config (uv)
├── .pre-commit-config.yaml        # Pre-commit hooks config
├── docs/                          # Documentation directory
│   └── TTS_HOOK_DOCUMENTATION.md  # Detailed technical documentation
├── hooks/                         # Reference copies of hook scripts
│   ├── tts-stop-hook.sh           # Main TTS playback hook
│   ├── tts-pretooluse-hook.sh     # PreToolUse narration hook
│   ├── tts-interrupt-hook.sh      # Interrupt handler hook
│   └── tts-session-end-hook.sh    # Session cleanup hook
├── scripts/                       # Python utilities
│   └── strip_markdown.py          # Markdown stripping with mistune
├── tests/                         # Test suite
│   └── test_strip_markdown.py     # Pytest tests for markdown stripping
├── kokoro-v1.0.onnx              # TTS model (310MB, not in git)
├── voices-v1.0.bin               # Voice embeddings (25MB, not in git)
└── .gitignore                    # Git ignore rules
```

## Development

This project uses [uv](https://astral.sh/uv) for Python package management and [pre-commit](https://pre-commit.com/) with [shellcheck](https://www.shellcheck.net/) for shell scripts, [ruff](https://docs.astral.sh/ruff/) for Python linting/formatting, and [pymarkdown](https://github.com/jackdewinter/pymarkdown) for markdown linting.

### Setup

```bash
# Install dev dependencies
uv sync --dev

# Install pre-commit hooks
uv run pre-commit install
```

### Running Linters

```bash
# Run all linters (shellcheck, ruff, pymarkdown)
uv run pre-commit run --all-files
```

### Running Tests

```bash
# Run pytest test suite
uv run pytest tests/ -v
```

## Contributing

Contributions are welcome. For bugs, issues, or feature requests, please submit a ticket at
[todo.sr.ht/~cg/claude-code-tts](https://todo.sr.ht/~cg/claude-code-tts).

## License

This project is licensed under the ISC License - see the LICENSE file for details.

## Credits

- **Kokoro TTS** - [hexgrad/kokoro](https://github.com/hexgrad/kokoro)
- **Claude Code** - [Anthropic](https://www.anthropic.com)

## Acknowledgments

Thanks to the Kokoro TTS team for creating an open-source text-to-speech model.
