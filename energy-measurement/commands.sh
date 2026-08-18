#!/usr/bin/env bash

set -euo pipefail
STAGE="${1:?stage required: build | test | train}"

# Model from the upstream Tests job matrix cell mirrored by this setup.
m=yolov5n

cd /project

case "$STAGE" in

  build)
    export UV_CACHE_DIR=/uv-cache
    uv venv /tmp/venv-build --python 3.11
    VIRTUAL_ENV=/tmp/venv-build uv pip install --offline -r requirements.txt \
        --extra-index-url https://download.pytorch.org/whl/cpu \
        --index-strategy unsafe-best-match
    VIRTUAL_ENV=/tmp/venv-build uv pip list
    ;;

  # test runs only against official weights; training is a separate stage,
  # so val/detect on the freshly trained best.pt are deliberately omitted.
  test)

    python val.py --imgsz 64 --batch 32 --weights $m.pt --device cpu
    python detect.py --imgsz 64 --weights $m.pt --device cpu
    python - <<EOF
from pathlib import Path

import numpy as np
from PIL import Image

from hubconf import _create
from utils.general import cv2

model = _create(name="$m", pretrained=True, channels=3, classes=80, autoshape=True, verbose=True)
imgs = [
    "data/images/zidane.jpg",  # filename
    Path("data/images/zidane.jpg"),  # Path
    cv2.imread("data/images/bus.jpg")[:, :, ::-1],  # OpenCV
    Image.open("data/images/bus.jpg"),  # PIL
    np.zeros((320, 640, 3)),  # numpy
]
results = model(imgs, size=320)
results.print()
results.save()
EOF
    python models/yolo.py --cfg $m.yaml
    python export.py --weights $m.pt --img 64 --include torchscript
    python - <<EOF
import torch

im = torch.zeros([1, 3, 64, 64])
model = torch.hub.load(".", "custom", path="$m", source="local")
print(model("data/images/bus.jpg"))
model(im)  # warmup, build grids for trace
torch.jit.trace(model, [im])
EOF

    python segment/val.py --imgsz 64 --batch 32 --weights ${m}-seg.pt --device cpu
    python segment/predict.py --imgsz 64 --weights ${m}-seg.pt --device cpu
    python export.py --weights ${m}-seg.pt --img 64 --include torchscript --device cpu

    python classify/val.py --imgsz 32 --weights ${m}-cls.pt --data ../datasets/mnist160
    python classify/predict.py --imgsz 32 --weights ${m}-cls.pt --source ../datasets/mnist160/test/7/60.png
    python classify/predict.py --imgsz 32 --weights ${m}-cls.pt --source data/images/bus.jpg
    python export.py --weights ${m}-cls.pt --img 64 --include torchscript
    python - <<EOF
import torch

model = torch.hub.load(".", "custom", path="${m}-cls.pt", source="local")
EOF
    ;;

  train)
    python train.py --imgsz 64 --batch 32 --weights $m.pt --cfg $m.yaml --epochs 1 --device cpu
    python segment/train.py --imgsz 64 --batch 32 --weights ${m}-seg.pt --cfg ${m}-seg.yaml --epochs 1 --device cpu
    python segment/train.py --imgsz 64 --batch 32 --weights '' --cfg ${m}-seg.yaml --epochs 1 --device cpu
    python classify/train.py --imgsz 32 --model ${m}-cls.pt --data mnist160 --epochs 1
    ;;

  *)
    echo "Stage desconhecido: $STAGE" >&2
    exit 1
    ;;
esac
