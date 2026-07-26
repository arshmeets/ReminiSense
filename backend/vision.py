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
