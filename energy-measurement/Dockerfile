# Dependencies, weights and datasets are fetched at image build time so
# measured stages can run with --network none.
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y software-properties-common && \
    add-apt-repository ppa:deadsnakes/ppa -y && \
    apt-get update && \
    apt-get install -y \
        python3.11 \
        python3.11-dev \
        python3.11-venv \
        python3-pip \
        git \
        curl \
        wget \
        unzip \
        libgl1 \
        libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

RUN pip install uv

RUN uv venv /venv --python 3.11
ENV VIRTUAL_ENV=/venv
ENV PATH="/venv/bin:$PATH"

ENV UV_CACHE_DIR=/uv-cache

COPY . /project
WORKDIR /project

RUN uv pip install -r requirements.txt \
        --extra-index-url https://download.pytorch.org/whl/cpu \
        --index-strategy unsafe-best-match

RUN wget -q -P /project \
        https://github.com/ultralytics/yolov5/releases/download/v7.0/yolov5n.pt \
        https://github.com/ultralytics/yolov5/releases/download/v7.0/yolov5n-seg.pt \
        https://github.com/ultralytics/yolov5/releases/download/v7.0/yolov5n-cls.pt

RUN mkdir -p /datasets && cd /datasets && \
    for z in coco128 coco128-seg mnist160; do \
        wget -q "https://github.com/ultralytics/assets/releases/download/v0.0.0/${z}.zip" && \
        unzip -q "${z}.zip" && rm "${z}.zip"; \
    done

ENV YOLOV5_CONFIG_DIR=/root/.config/Ultralytics
RUN mkdir -p /root/.config/Ultralytics && \
    wget -q -P /root/.config/Ultralytics \
        https://github.com/ultralytics/assets/releases/download/v0.0.0/Arial.ttf

RUN python -c "import torch, cv2, matplotlib, ultralytics" || true

