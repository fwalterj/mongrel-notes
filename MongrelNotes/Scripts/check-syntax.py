#!/usr/bin/env python3
"""
check-syntax.py — Swift structural sanity checks for MongrelNotes.

Checks performed:
  1. Brace balance (correctly skips string literals, raw strings, comments)
  2. No UIColor usage (macOS target must use NSColor)
  3. No NSColor(hue:saturation:brightness:opacity:) — should be alpha:
  4. No bare VaultStore() initialisation with no arguments

Exit code 0 if all files pass, 1 if any fail.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).parent.parent
SWIFT_FILES = sorted(ROOT.rglob("*.swift"))

errors = []

# ── String literal helpers ────────────────────────────────────────────────────

def _skip_raw_string(src: str, i: int, n: int, hashes: int, multiline: bool) -> int:
    """
    Skip the body of a raw string after the opening quote(s) have been consumed.
    hashes: number of # delimiters on each side.
    multiline: True for #\"\"\"...\"\"\"# variants.
    Returns index just past the closing delimiter.
    """
    close = ('"""' if multiline else '"') + '#' * hashes
    clen = len(close)
    while i < n and src[i:i + clen] != close:
        i += 1
    return i + clen


def _skip_string(src: str, i: int, n: int) -> int:
    """
    Skip a regular "..." string body (caller has already consumed the opening
    quote).  Correctly handles:
      \\x  — backslash-escaped character
      \\(  — string interpolation: skip forward to the balanced closing )
             recursively handling nested strings inside the interpolation
    Returns index just past the closing quote (or n if the string is unterminated).
    """
    while i < n:
        c = src[i]
        if c == '\\':
            if i + 1 < n and src[i + 1] == '(':
                # String interpolation: skip to the matching ')'
                i = _skip_interpolation(src, i + 2, n)
                continue
            else:
                i += 2          # skip backslash + next char
                continue
        if c == '"':
            return i + 1        # past the closing quote
        i += 1
    return n                    # unterminated string


def _skip_interpolation(src: str, i: int, n: int) -> int:
    """
    Skip a Swift string interpolation expression body starting after the '('.
    Matches nested parens and any string literals inside (including raw strings,
    multi-line strings, and further interpolated strings).
    Returns index just past the closing ')'.
    """
    depth = 1
    while i < n and depth > 0:
        c = src[i]

        # Nested raw string inside interpolation
        if c == '#':
            j = i
            while j < n and src[j] == '#':
                j += 1
            hashes = j - i
            if j < n and src[j] == '"':
                multiline = src[j:j + 3] == '"""'
                start = j + (3 if multiline else 1)
                i = _skip_raw_string(src, start, n, hashes, multiline)
                continue

        # Multi-line string inside interpolation
        if src[i:i + 3] == '"""':
            i += 3
            while i + 2 < n and src[i:i + 3] != '"""':
                i += 1
            i += 3
            continue

        # Regular string inside interpolation
        if c == '"':
            i = _skip_string(src, i + 1, n)
            continue

        if c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0:
                return i + 1    # past the ')'
        i += 1
    return i


# ── Brace balance ──────────────────────────────────────────────────────────────

def brace_balance(src: str) -> int:
    """
    Count structural { / } in Swift source, correctly skipping:
      - // line comments
      - /* ... */ block comments
      - "..."  regular string literals (with \\-escape handling)
      - \"\"\"...\"\"\"  multi-line string literals
      - #"..."# (and ##...## etc.) raw string literals
    """
    depth = 0
    i = 0
    n = len(src)

    while i < n:
        c = src[i]

        # ── Line comment ──────────────────────────────────────────────────────
        if c == '/' and i + 1 < n and src[i + 1] == '/':
            while i < n and src[i] != '\n':
                i += 1
            continue

        # ── Block comment ─────────────────────────────────────────────────────
        if c == '/' and i + 1 < n and src[i + 1] == '*':
            i += 2
            while i + 1 < n and not (src[i] == '*' and src[i + 1] == '/'):
                i += 1
            i += 2
            continue

        # ── Raw string  #"..."#  ##"..."##  etc. ─────────────────────────────
        # Count leading # characters followed by " or """
        if c == '#':
            j = i
            while j < n and src[j] == '#':
                j += 1
            hashes = j - i          # number of # delimiters
            if j < n and src[j] == '"':
                close_delim = '"' + '#' * hashes
                # Multi-line raw: #"""..."""#
                if src[j:j + 3] == '"""':
                    close_delim = '"""' + '#' * hashes
                    i = j + 3
                    while i < n and src[i:i + len(close_delim)] != close_delim:
                        i += 1
                    i += len(close_delim)
                else:
                    i = j + 1
                    while i < n and src[i:i + len(close_delim)] != close_delim:
                        i += 1
                    i += len(close_delim)
                continue

        # ── Multi-line string  """...""" ──────────────────────────────────────
        if src[i:i + 3] == '"""':
            i += 3
            while i + 2 < n and src[i:i + 3] != '"""':
                i += 1
            i += 3
            continue

        # ── Regular string  "..." ─────────────────────────────────────────────
        if c == '"':
            i = _skip_string(src, i + 1, n)
            continue                 # _skip_string already consumed closing '"'

        # ── Structural braces ─────────────────────────────────────────────────
        elif c == '{':
            depth += 1
        elif c == '}':
            depth -= 1

        i += 1

    return depth


# ── Main check loop ────────────────────────────────────────────────────────────

for path in SWIFT_FILES:
    rel = path.relative_to(ROOT)
    try:
        content = path.read_text(encoding='utf-8')
    except Exception as e:
        errors.append(f"{rel}: could not read — {e}")
        continue

    # 1. Brace balance
    balance = brace_balance(content)
    if balance != 0:
        errors.append(f"{rel}: brace mismatch (net {balance:+d})")

    # 2. UIColor usage — macOS requires NSColor
    import re
    if re.search(r'\bUIColor\b', content):
        errors.append(f"{rel}: uses UIColor — use NSColor for macOS targets")

    # 3. NSColor(… opacity: …) — should be alpha:
    if re.search(r'NSColor\s*\([^)]*\bopacity\s*:', content):
        errors.append(f"{rel}: NSColor uses `opacity:` parameter — should be `alpha:`")

    # 4. Bare VaultStore() — dummy initialisation anti-pattern
    if re.search(r'VaultStore\(\s*\)', content):
        errors.append(f"{rel}: bare VaultStore() init detected — pass a real Vault")


# ── Result ─────────────────────────────────────────────────────────────────────

if errors:
    print(f"\n❌  {len(errors)} issue(s) found:\n")
    for e in errors:
        print(f"  • {e}")
    sys.exit(1)
else:
    print(f"✅  All {len(SWIFT_FILES)} Swift files passed structural checks.")
    sys.exit(0)
