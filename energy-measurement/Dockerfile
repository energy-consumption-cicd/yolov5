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

# Latest 3.10 patch released before the tag commit (2022-08-17); stdlib venv, so pip starts at the bundled version.
RUN uv python install 3.10.6 && "$(uv python find 3.10.6)" -m venv /venv
ENV VIRTUAL_ENV=/venv
ENV PATH="/venv/bin:$PATH"

# The tag pins no versions: these are the releases current at the tag commit, with the CPU builds of torch.
RUN pip download --no-deps --only-binary=:all: --dest /wheelhouse \
        --extra-index-url https://download.pytorch.org/whl/cpu \
        pip==22.2.2 absl-py==1.2.0 asttokens==2.0.8 backcall==0.2.0 \
        cachetools==5.2.0 certifi==2022.6.15 charset-normalizer==2.1.0 cycler==0.11.0 \
        decorator==5.1.1 executing==0.10.0 fonttools==4.35.0 google-auth==2.10.0 \
        google-auth-oauthlib==0.4.6 grpcio==1.47.0 idna==3.3 ipython==8.4.0 \
        jedi==0.18.1 kiwisolver==1.4.4 markdown==3.4.1 markupsafe==2.1.1 \
        matplotlib==3.5.3 matplotlib-inline==0.1.5 numpy==1.23.2 oauthlib==3.2.0 \
        opencv-python==4.6.0.66 packaging==21.3 pandas==1.4.3 parso==0.8.3 \
        pexpect==4.8.0 pickleshare==0.7.5 pillow==9.2.0 prompt-toolkit==3.0.30 \
        protobuf==3.20.1 psutil==5.9.1 ptyprocess==0.7.0 pure-eval==0.2.2 \
        pyasn1==0.4.8 pyasn1-modules==0.2.8 pygments==2.13.0 pyparsing==3.0.9 \
        python-dateutil==2.8.2 pytz==2022.2.1 pyyaml==6.0 requests==2.28.1 \
        requests-oauthlib==1.3.1 rsa==4.9 scipy==1.9.0 seaborn==0.11.2 \
        setuptools==65.0.2 six==1.16.0 stack-data==0.4.0 tensorboard==2.9.0 \
        tensorboard-data-server==0.6.1 tensorboard-plugin-wit==1.8.1 thop==0.1.1.post2207130030 torch==1.12.1+cpu \
        torchvision==0.13.1+cpu tqdm==4.64.0 traitlets==5.3.0 typing-extensions==4.3.0 \
        urllib3==1.26.11 wcwidth==0.2.5 werkzeug==2.2.2 wheel==0.37.1
RUN test "$(ls /wheelhouse | grep -vc '\.whl$')" -eq 0

COPY . /project
WORKDIR /project

# From here on pip resolves from /wheelhouse only, in the image and in the measured build stage.
ENV PIP_NO_INDEX=1 PIP_FIND_LINKS=/wheelhouse PIP_DISABLE_PIP_VERSION_CHECK=1

# Without network, as in the measured build stage, so a missing wheel fails the image and not a run.
RUN --network=none python -m pip install --upgrade pip wheel && \
    pip install -r requirements.txt --extra-index-url https://download.pytorch.org/whl/cpu

# yolov5n-cls.pt comes from release v6.2: at this tag attempt_download() queries release v6.1, which has no classification weights.
RUN wget -q -P /project \
        https://github.com/ultralytics/yolov5/releases/download/v6.2/yolov5n.pt \
        https://github.com/ultralytics/yolov5/releases/download/v6.2/yolov5n-cls.pt && \
    cd /project && \
    echo "4f180cf23ba0717ada0badd6c685026d73d48f184d00fc159c2641284b2ac0a3  yolov5n.pt" | sha256sum -c - && \
    echo "77b15f65325b37c24e616cbe0e5349d63c35508607458b9f2bcb03875ab75f33  yolov5n-cls.pt" | sha256sum -c -

RUN cd /datasets && \
    wget -q https://github.com/ultralytics/yolov5/releases/download/v1.0/mnist2560.zip && \
    echo "b9c2fb4b0a201ebdbb924f3e80aa828c227cd2714344270e4cae8af1356f8508  mnist2560.zip" | sha256sum -c - && \
    unzip -q mnist2560.zip && rm mnist2560.zip

RUN python -c "import torch, cv2, matplotlib" || true

# Build context: a clone of branch release-6.2.0, not a git worktree.
#   docker build -t yolov5-measurement-6.2.0 -f energy-measurement/Dockerfile .
