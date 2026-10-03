# Dependencies, weights and datasets are fetched at image build time so
# measured stages can run with --network none.
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# build-essential only serves source-only dependencies of one release; kept here so the layer is shared.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        git \
        curl \
        wget \
        unzip \
        libgl1 \
        libglib2.0-0 \
        build-essential \
    && rm -rf /var/lib/apt/lists/*

# uv only provides the interpreter; no measured stage calls it.
RUN curl -LsSf https://astral.sh/uv/0.12.9/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh
ENV UV_PYTHON_INSTALL_DIR=/opt/python

RUN mkdir -p /datasets && cd /datasets && \
    wget -q https://github.com/ultralytics/assets/releases/download/v0.0.0/coco128.zip && \
    echo "61e5e3028863d8ffc3b81d6a514603954889f0edd5e4b44c4ce60b2da99aeb8e  coco128.zip" | sha256sum -c - && \
    unzip -q coco128.zip && rm coco128.zip

ENV YOLOV5_CONFIG_DIR=/root/.config/Ultralytics
RUN mkdir -p /root/.config/Ultralytics && \
    wget -q -P /root/.config/Ultralytics \
        https://github.com/ultralytics/assets/releases/download/v0.0.0/Arial.ttf && \
    echo "525979822591a3447cfc49d943d6f7683508e25543407871c0ed8fed05fd2bd9  /root/.config/Ultralytics/Arial.ttf" | sha256sum -c -

# Latest 3.9 patch released before the tag commit (2022-02-22); stdlib venv, so pip starts at the bundled version.
RUN uv python install 3.9.10 && "$(uv python find 3.9.10)" -m venv /venv
ENV VIRTUAL_ENV=/venv
ENV PATH="/venv/bin:$PATH"

# The tag pins no versions: these are the releases current at the tag commit, with the CPU builds of torch.
# The second pip command of the job downgrades packages the first one installs, so both versions are kept.
# Longer read timeout for the image build only: the large wheels of this release stalled at the default.
RUN PIP_DEFAULT_TIMEOUT=300 pip download --no-deps --only-binary=:all: --dest /wheelhouse \
        --extra-index-url https://download.pytorch.org/whl/cpu \
        pip==22.0.3 absl-py==1.0.0 cachetools==5.0.0 certifi==2021.10.8 \
        charset-normalizer==2.0.12 cycler==0.11.0 fonttools==4.29.1 google-auth==2.6.0 \
        google-auth-oauthlib==0.4.6 grpcio==1.44.0 idna==3.3 importlib-metadata==4.11.1 \
        kiwisolver==1.3.2 markdown==3.3.6 matplotlib==3.5.1 numpy==1.22.2 \
        oauthlib==3.2.0 opencv-python==4.5.4.60 packaging==21.3 pandas==1.4.1 \
        pillow==9.0.1 protobuf==3.19.4 pyasn1==0.4.8 pyasn1-modules==0.2.8 \
        pyparsing==3.0.7 python-dateutil==2.8.2 pytz==2021.3 pyyaml==6.0 \
        requests==2.27.1 requests-oauthlib==1.3.1 rsa==4.8 scipy==1.8.0 \
        seaborn==0.11.2 setuptools==60.9.3 six==1.16.0 tensorboard==2.8.0 \
        tensorboard-data-server==0.6.1 tensorboard-plugin-wit==1.8.1 thop==0.0.31.post2005241907 torch==1.10.2+cpu \
        torchvision==0.11.3+cpu tqdm==4.62.3 typing-extensions==4.1.1 urllib3==1.26.8 \
        werkzeug==2.0.3 wheel==0.37.1 zipp==3.7.0
# Longer read timeout for the image build only: the large wheels of this release stalled at the default.
RUN PIP_DEFAULT_TIMEOUT=300 pip download --no-deps --only-binary=:all: --dest /wheelhouse \
        absl-py==0.15.0 astunparse==1.6.3 cachetools==4.2.4 flatbuffers==1.12 \
        gast==0.4.0 google-auth==1.35.0 google-pasta==0.2.0 h5py==3.1.0 \
        keras==2.6.0 keras-preprocessing==1.1.2 numpy==1.19.5 onnx==1.11.0 \
        opt-einsum==3.3.0 six==1.15.0 tensorboard==2.6.0 tensorflow-cpu==2.6.3 \
        tensorflow-estimator==2.6.0 typing-extensions==3.10.0.2

# Published as source only for this interpreter; built once here so the measured build installs wheels only.
RUN python -m venv /tmp/wheel-build && \
    /tmp/wheel-build/bin/pip install --no-index --find-links /wheelhouse wheel && \
    /tmp/wheel-build/bin/pip wheel --no-deps --wheel-dir /wheelhouse clang==5.0 termcolor==1.1.0 wrapt==1.12.1 && \
    rm -rf /tmp/wheel-build
RUN test "$(ls /wheelhouse | grep -vc '\.whl$')" -eq 0

COPY . /project
WORKDIR /project

# From here on pip resolves from /wheelhouse only, in the image and in the measured build stage.
ENV PIP_NO_INDEX=1 PIP_FIND_LINKS=/wheelhouse PIP_DISABLE_PIP_VERSION_CHECK=1
# An unreachable --find-links URL is retried with backoff; offline that is idle time inside the stage.
ENV PIP_RETRIES=0

# Without network, as in the measured build stage, so a missing wheel fails the image and not a run.
RUN --network=none python -m pip install --upgrade pip && \
    pip install -qr requirements.txt -f https://download.pytorch.org/whl/cpu/torch_stable.html && \
    pip install -q onnx tensorflow-cpu keras==2.6.0

# yolov5s.pt is the model hubconf.py builds at this tag.
RUN wget -q -P /project \
        https://github.com/ultralytics/yolov5/releases/download/v6.1/yolov5n.pt \
        https://github.com/ultralytics/yolov5/releases/download/v6.1/yolov5s.pt && \
    cd /project && \
    echo "4f180cf23ba0717ada0badd6c685026d73d48f184d00fc159c2641284b2ac0a3  yolov5n.pt" | sha256sum -c - && \
    echo "8b3b748c1e592ddd8868022e8732fde20025197328490623cc16c6f24d0782ee  yolov5s.pt" | sha256sum -c -

RUN python -c "import torch, cv2, matplotlib, tensorflow, onnx" || true

# Build context: a clone of branch release-6.1.0, not a git worktree.
#   docker build -t yolov5-measurement-6.1.0 -f energy-measurement/Dockerfile .
