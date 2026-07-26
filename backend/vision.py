"""Thin helper: base64 frame -> temp image file for byllm's Image type."""
import base64
import os
import tempfile


def save_b64(b64: str) -> str:
    if "," in b64[:64]:  # strip data-url prefix
        b64 = b64.split(",", 1)[1]
    f = tempfile.NamedTemporaryFile(
        suffix=".jpg", delete=False, dir=tempfile.gettempdir()
    )
    f.write(base64.b64decode(b64))
    f.close()
    return f.name


def cleanup(path: str) -> None:
    try:
        os.unlink(path)
    except OSError:
        pass


import re as _re

_SENSITIVE = _re.compile(
    r"(\$\s?\d[\d,\.]*|\b\d{3}[- ]?\d{2}[- ]?\d{4}\b|\b(?:\d[ -]?){13,19}\b|"
    r"\b(password|ssn|account|routing|diagnos\w+|cancer|debt|divorce|lawsuit)\b[^,.;]*)",
    _re.IGNORECASE,
)


def strip_sensitive(text: str) -> str:
    """Deterministic fallback persona filter: drop clauses with sensitive markers."""
    out = _SENSITIVE.sub("", text)
    out = _re.sub(r"[,\s]*\d[\d,\.]*", "", out)          # orphaned number fragments
    out = _re.sub(r"\s+(and|or|about)\s*$", "", out.strip(" ,;-"))
    out = _re.sub(r"\s{2,}", " ", out).strip(" ,;-")
    return out or "a nice visit"
