# Hook Scripts

This directory contains reference copies of the TTS hook scripts that are installed to `~/.claude/hooks/` by the installation script.

## Files

- `kokoro-tts-hook.sh` - Main TTS playback hook (Stop event)
- `tts-pretooluse-hook.sh` - PreToolUse narration hook (PreToolUse event)
- `tts-interrupt-hook.sh` - Interrupt handler hook (UserPromptSubmit event)

## Usage

These files are for reference only. The actual hooks used by Claude Code are located in `~/.claude/hooks/`.

To install or update the hooks, run:

```bash
./install.sh
```

## Modifications

If you modify these hooks:
1. Update the corresponding section in `install.sh`
2. Run `./install.sh` to apply changes to the global hooks
3. Or manually copy the modified hook to `~/.claude/hooks/`

## Documentation

See `docs/TTS_HOOK_DOCUMENTATION.md` for detailed documentation on how these hooks work.
