#!/usr/bin/env bash

set -euo pipefail
STAGE="${1:?stage required: build | test | train}"

# Model of the matrix cell (ubuntu-latest, Python 3.10) of job Tests, ci-testing.yml at tag v6.2 (d3ea0df8).
m=yolov5n

cd /project

case "$STAGE" in

  build)
    python -m venv /tmp/venv-build
    export VIRTUAL_ENV=/tmp/venv-build PATH="/tmp/venv-build/bin:$PATH"
    # ci-testing.yml:84-88, resolved from /wheelhouse (PIP_NO_INDEX and PIP_FIND_LINKS of the image)
    python -m pip install --upgrade pip wheel
    pip install -r requirements.txt --extra-index-url https://download.pytorch.org/whl/cpu
    # ci-testing.yml:102
    pip list
    ;;

  # test runs only against official weights; training is a separate stage,
  # so val/detect on the freshly trained best.pt are deliberately omitted.
  test)

    # ci-testing.yml:110-115
    python val.py --imgsz 64 --batch 32 --weights $m.pt --device cpu
    python detect.py --imgsz 64 --weights $m.pt --device cpu
    # ci-testing.yml:116, inline without the remote image source
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
    # ci-testing.yml:118-119
    python models/yolo.py --cfg $m.yaml
    python export.py --weights $m.pt --img 64 --include torchscript
    # ci-testing.yml:120-125
    python - <<EOF
import torch

model = torch.hub.load(".", "custom", path="$m", source="local")
print(model("data/images/bus.jpg"))
EOF

    # ci-testing.yml:132-135, official weights in place of best.pt
    python classify/val.py --imgsz 32 --weights ${m}-cls.pt --data ../datasets/mnist2560
    python classify/predict.py --imgsz 32 --weights ${m}-cls.pt --source ../datasets/mnist2560/test/7/60.png
    python classify/predict.py --imgsz 32 --weights ${m}-cls.pt --source data/images/bus.jpg
    python export.py --weights ${m}-cls.pt --img 64 --imgsz 224 --include torchscript
    ;;

  train)
    # ci-testing.yml:109
    python train.py --imgsz 64 --batch 32 --weights $m.pt --cfg $m.yaml --epochs 1 --device cpu
    # ci-testing.yml:131
    python classify/train.py --imgsz 32 --model ${m}-cls.pt --data mnist2560 --epochs 1
    ;;

  *)
    echo "Unknown stage: $STAGE" >&2
    exit 1
    ;;
esac
