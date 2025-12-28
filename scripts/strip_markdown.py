#!/usr/bin/env python3
"""Strip markdown formatting from text for TTS output.

Usage:
    echo "**bold** text" | python strip_markdown.py
    cat file.md | python strip_markdown.py
"""

import re
import sys

import mistune
from mistune.plugins.formatting import strikethrough as strikethrough_plugin


class PlainTextRenderer(mistune.HTMLRenderer):
    """Render markdown as plain text suitable for TTS."""

    def text(self, text):
        return text

    def emphasis(self, text):
        return text

    def strong(self, text):
        return text

    def codespan(self, text):
        return ""  # Remove inline code

    def block_code(self, code, info=None):
        return ""  # Remove code blocks

    def link(self, text, url, title=None):
        return text or ""

    def image(self, alt, url, title=None):
        return alt or ""

    def heading(self, text, level, **attrs):
        return text + ". "

    def paragraph(self, text):
        return text + " "

    def list(self, text, ordered, **attrs):
        return text

    def list_item(self, text, **attrs):
        return text.strip() + ". "

    def thematic_break(self):
        return ""

    def block_quote(self, text):
        return text

    def linebreak(self):
        return " "

    def softbreak(self):
        return " "

    def block_html(self, html):
        return ""  # Remove raw HTML blocks

    def inline_html(self, html):
        return ""  # Remove inline HTML tags

    def strikethrough(self, text):
        return text  # Keep text, remove ~~ markers


def strip_markdown(text: str) -> str:
    """Convert markdown to plain text for TTS.

    Args:
        text: Markdown-formatted text

    Returns:
        Plain text suitable for TTS
    """
    # Pre-process: remove bare URLs
    text = re.sub(r"https?://[^\s\)]+", "", text)

    # Pre-process: remove file paths (backtick-wrapped and bare)
    text = re.sub(r"`[~/][^`]+`", "", text)
    # Bare paths: ~/path or /path (must have / in the path portion)
    # Handles both ~/foo/bar and /usr/bin patterns
    text = re.sub(r"(?:^|\s)~/[a-zA-Z0-9_./-]+", " ", text)  # ~/path
    text = re.sub(r"(?:^|\s)/[a-zA-Z0-9_.-]+/[a-zA-Z0-9_./-]*", " ", text)  # /path/...

    # Pre-process: remove tables (pipe-based)
    text = re.sub(r"^\|.*\|$", "", text, flags=re.MULTILINE)
    text = re.sub(r"^\s*\|[-:\s|]+\|\s*$", "", text, flags=re.MULTILINE)

    # Parse markdown with custom renderer
    # Enable strikethrough plugin to handle ~~deleted~~ syntax
    renderer = PlainTextRenderer()
    md = mistune.create_markdown(renderer=renderer, plugins=[strikethrough_plugin])
    result = md(text)

    # Post-process: remove leftover brackets and backticks
    result = re.sub(r"[`\(\)\[\]]", "", result)

    # Post-process: normalize whitespace
    result = re.sub(r"\s+", " ", result)

    # Remove emoji patterns (checkmarks, X marks, warning signs)
    result = re.sub(r"[\u2714\u2705]", "", result)  # Check marks
    result = re.sub(r"[\u274c\u274e]", "", result)  # X marks
    result = re.sub(r"[\u26a0]", "", result)  # Warning sign

    return result.strip()


def main():
    """Read from stdin, strip markdown, write to stdout."""
    text = sys.stdin.read()
    print(strip_markdown(text))


if __name__ == "__main__":
    main()
