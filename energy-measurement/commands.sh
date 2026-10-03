#!/usr/bin/env bash

set -euo pipefail
STAGE="${1:?stage required: build | test | train}"

# Model of the matrix cell (ubuntu-latest, Python 3.9) of job cpu-tests, ci-testing.yml at tag v6.1 (3752807c).
m=yolov5n

cd /project

case "$STAGE" in

  build)
    python -m venv /tmp/venv-build
    export VIRTUAL_ENV=/tmp/venv-build PATH="/tmp/venv-build/bin:$PATH"
    # ci-testing.yml:52-57, resolved from /wheelhouse (PIP_NO_INDEX and PIP_FIND_LINKS of the image)
    python -m pip install --upgrade pip
    pip install -qr requirements.txt -f https://download.pytorch.org/whl/cpu/torch_stable.html
    pip install -q onnx tensorflow-cpu keras==2.6.0
    python --version
    pip --version
    pip list
    ;;

  # test runs only against official weights; training is a separate stage,
  # so val/detect on the freshly trained best.pt are deliberately omitted.
  test)

    # ci-testing.yml:77
    python val.py --img 64 --batch 32 --weights $m.pt --device cpu
    # ci-testing.yml:80
    python detect.py --weights $m.pt --device cpu
    # ci-testing.yml:82, inline without the remote image source
    python - <<EOF
from pathlib import Path

import numpy as np
from PIL import Image

from hubconf import _create
import cv2

model = _create(name="yolov5s", pretrained=True, channels=3, classes=80, autoshape=True, verbose=True)
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
    # ci-testing.yml:84-86
    python models/yolo.py --cfg $m.yaml
    python models/tf.py --weights $m.pt
    python export.py --weights $m.pt --img 64 --include torchscript onnx
    # ci-testing.yml:88-91
    python - <<EOF
import torch
EOF
    ;;

  train)
    # ci-testing.yml:75
    python train.py --img 64 --batch 32 --weights $m.pt --cfg $m.yaml --epochs 1 --device cpu
    ;;

  *)
    echo "Unknown stage: $STAGE" >&2
    exit 1
    ;;
esac
