FROM pytorch/pytorch:2.6.0-cuda12.4-cudnn9-runtime

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV PIP_DISABLE_PIP_VERSION_CHECK=1

ENV HF_HOME=/workspace/cache/huggingface
ENV HF_DATASETS_CACHE=/workspace/cache/huggingface/datasets
ENV TORCH_HOME=/workspace/cache/torch
ENV PIP_CACHE_DIR=/workspace/cache/pip
ENV TOKENIZERS_PARALLELISM=true

WORKDIR /workspace

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    git-lfs \
    wget \
    curl \
    unzip \
    nano \
    vim \
    htop \
    build-essential \
    libsndfile1 \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

RUN python -m pip install --upgrade pip

COPY requirements.txt /tmp/requirements.txt

RUN pip install -r /tmp/requirements.txt

CMD ["/bin/bash"]
