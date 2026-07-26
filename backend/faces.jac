"""Face perception (YuNet + SFace) — shared module, extracted from app.jac."""

import cv2;
import numpy as np;
import base64;
import time;


glob DET_PATH: str = "models/face_detection_yunet_2023mar.onnx";
glob REC_PATH: str = "models/face_recognition_sface_2021dec.onnx";

# Wearable frames are shot close-up and often backlit, which sinks the face
# into shadow and hides it from the detector. Equalising the luminance channel
# first recovers the detection; measured on a hard backlit frame, this is the
# difference between needing a 0.15 score threshold and a comfortable 0.5.
glob DET_SCORE: float = 0.5;

# SFace's published cosine threshold for a same-identity match.
glob FACE_THRESHOLD: float = 0.363;

# Model handles are built once and cached. A dict is used rather than a
# rebindable glob so the lazy init needs no global reassignment.
glob _cache: dict = {};


# ---------------------------------------------------------------- perception

def _detector() -> any {
    if "det" not in _cache {
        _cache["det"] = cv2.FaceDetectorYN.create(DET_PATH, "", (320, 320), DET_SCORE, 0.3, 5000);
    }
    return _cache["det"];
}


# Lift the face out of the backlight before detection: equalise L in LAB space,
# leaving colour untouched so the embedding still sees a natural face.
def _delight(img: any) -> any {
    lab: any = cv2.cvtColor(img, cv2.COLOR_BGR2LAB);
    parts: any = cv2.split(lab);
    eq: any = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(8, 8)).apply(parts[0]);
    merged: any = cv2.merge((eq, parts[1], parts[2]));
    return cv2.cvtColor(merged, cv2.COLOR_LAB2BGR);
}


def _recognizer() -> any {
    if "rec" not in _cache {
        _cache["rec"] = cv2.FaceRecognizerSF.create(REC_PATH, "");
    }
    return _cache["rec"];
}


# Returns a 128-d face embedding for the largest face, or [] if none found.
def embed_face(jpeg_b64: str) -> list[float] {
    raw = base64.b64decode(jpeg_b64);
    buf: any = np.frombuffer(raw, dtype=np.uint8);
    decoded: any = cv2.imdecode(buf, cv2.IMREAD_COLOR);
    if decoded is None {
        return [];
    }
    img: any = _delight(decoded);

    det: any = _detector();
    shape: any = img.shape;
    det.setInputSize((int(shape[1]), int(shape[0])));
    faces: any = det.detect(img)[1];
    if faces is None or len(faces) == 0 {
        return [];
    }

    # Largest detected face wins - the wearer is looking at whoever is closest.
    best: any = faces[0];
    best_area: float = 0.0;
    for f in faces {
        box: any = f;
        area: float = float(box[2]) * float(box[3]);
        if area > best_area {
            best_area = area;
            best = box;
        }
    }

    rec: any = _recognizer();
    feat: any = rec.feature(rec.alignCrop(img, best));
    flat: any = feat.flatten().tolist();
    out: list[float] = [];
    for v in flat {
        out.append(float(v));
    }
    return out;
}



def cosine(a: list[float], b: list[float]) -> float {
    if len(a) == 0 or len(b) == 0 or len(a) != len(b) {
        return 0.0;
    }
    dot: float = 0.0;
    na: float = 0.0;
    nb: float = 0.0;
    for i in range(len(a)) {
        dot += a[i] * b[i];
        na += a[i] * a[i];
        nb += b[i] * b[i];
    }
    if na == 0.0 or nb == 0.0 {
        return 0.0;
    }
    return dot / ((na ** 0.5) * (nb ** 0.5));
}
