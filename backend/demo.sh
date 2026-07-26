#!/usr/bin/env bash
# ReminiSense demo helpers. Rebuild the graph, enrol a face, test a frame -
# all without the phone.
#
#   ./demo.sh reset                  wipe + reseed the demo graph
#   ./demo.sh roster                 show what is in the graph
#   ./demo.sh enroll <name> <img>    enrol a face from a photo
#   ./demo.sh look <img>             recognise a frame, print the spoken line
#   ./demo.sh caption <text> [lang]  clean/translate speech for the display
#   ./demo.sh hear <transcript>      log a conversation into the graph
#   ./demo.sh who <name|last>        recall card for a person
#   ./demo.sh ask <question>         free-text query over everyone met
#
# HOST defaults to localhost; override to hit the Mac from another machine:
#   HOST=10.0.0.5 ./demo.sh look frame.jpg

set -euo pipefail
cd "$(dirname "$0")"

HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8000}"
BASE="http://${HOST}:${PORT}"
PY=".jac/venv/bin/python"

# Downscale to 512px on the longest edge and base64 it - same as the iOS app.
b64() {
  "$PY" - "$1" <<'PY'
import sys, cv2, base64
img = cv2.imread(sys.argv[1])
if img is None:
    sys.exit(f"cannot read image: {sys.argv[1]}")
h, w = img.shape[:2]
s = 512 / max(h, w)
if s < 1:
    img = cv2.resize(img, (int(w * s), int(h * s)), interpolation=cv2.INTER_AREA)
ok, buf = cv2.imencode(".jpg", img, [cv2.IMWRITE_JPEG_QUALITY, 85])
print(base64.b64encode(buf.tobytes()).decode(), end="")
PY
}

post() { curl -s -X POST "${BASE}/walker/$1" -H 'Content-Type: application/json' -d "@$2"; }

reports() { "$PY" -c "import sys,json;d=json.load(sys.stdin);r=d.get('data',{}).get('reports',[]);print(json.dumps(r[0],indent=2) if r else json.dumps(d)[:300])"; }

case "${1:-}" in
  reset)
    echo '{}' > /tmp/rs_empty.json
    # Two requests on purpose: deletes land at commit, so wiping and seeding
    # in one walker would destroy the freshly seeded nodes.
    echo "wiping..."; post Reset /tmp/rs_empty.json | reports
    echo "seeding..."; post Seed /tmp/rs_empty.json | reports
    ;;
  roster)
    echo '{}' > /tmp/rs_empty.json
    post Roster /tmp/rs_empty.json | reports
    ;;
  enroll)
    name="${2:?usage: ./demo.sh enroll <name> <image>}"
    img="${3:?usage: ./demo.sh enroll <name> <image>}"
    "$PY" -c "
import json,sys
print(json.dumps({'name':sys.argv[1],'frame_b64':sys.argv[2],
                  'relationship':'enrolled on site','closeness':0.9,'recency':1.0}))
" "$name" "$(b64 "$img")" > /tmp/rs_enroll.json
    post Enroll /tmp/rs_enroll.json | reports
    ;;
  look)
    img="${2:?usage: ./demo.sh look <image>}"
    "$PY" -c "import json,sys;print(json.dumps({'frame_b64':sys.argv[1]}))" "$(b64 "$img")" > /tmp/rs_look.json
    post Recognize /tmp/rs_look.json | reports
    ;;
  caption)
    txt="${2:?usage: ./demo.sh caption <text> [lang]}"
    "$PY" -c "import json,sys;print(json.dumps({'text':sys.argv[1],'lang':sys.argv[2]}))" "$txt" "${3:-en}" > /tmp/rs_cap.json
    post caption /tmp/rs_cap.json | reports
    ;;
  hear)
    txt="${2:?usage: ./demo.sh hear <transcript>}"
    "$PY" -c "import json,sys;print(json.dumps({'transcript':sys.argv[1]}))" "$txt" > /tmp/rs_hear.json
    post ingest /tmp/rs_hear.json | reports
    ;;
  who)
    "$PY" -c "import json,sys;print(json.dumps({'name':sys.argv[1]}))" "${2:-last}" > /tmp/rs_who.json
    post recall /tmp/rs_who.json | reports
    ;;
  ask)
    q="${2:?usage: ./demo.sh ask <question>}"
    "$PY" -c "import json,sys;print(json.dumps({'question':sys.argv[1]}))" "$q" > /tmp/rs_ask.json
    post query /tmp/rs_ask.json | reports
    ;;
  *)
    sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
