ARG UBUNTU_VERSION=22.04
ARG CUDA_VERSION=12.6.3
ARG BASE_CUDA_DEV_CONTAINER=nvidia/cuda:${CUDA_VERSION}-devel-ubuntu${UBUNTU_VERSION}
ARG BASE_CUDA_RUN_CONTAINER=nvidia/cuda:${CUDA_VERSION}-runtime-ubuntu${UBUNTU_VERSION}

# Default covers Ampere (A100=80, RTX3090=86), Ada (RTX4090=89), Hopper (H100=90), Blackwell (GB10=100)
# Pass --build-arg CMAKE_CUDA_ARCHITECTURES=native for an optimized single-GPU local build
ARG CMAKE_CUDA_ARCHITECTURES=80;86;89;90;100

# ── Build stage ──────────────────────────────────────────────────────────────
FROM ${BASE_CUDA_DEV_CONTAINER} AS builder

ARG CMAKE_CUDA_ARCHITECTURES

RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    libssl-dev \
    libcurl4-openssl-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
RUN git clone --depth=1 https://github.com/ggml-org/llama.cpp .

RUN cmake -B build \
    -DGGML_CUDA=ON \
    -DGGML_RPC=ON \
    -DGGML_BACKEND_DL=ON \
    -DGGML_CPU_ALL_VARIANTS=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CUDA_ARCHITECTURES="${CMAKE_CUDA_ARCHITECTURES}" \
    && cmake --build build --config Release -j$(nproc) \
        --target llama-server rpc-server

# ── Runtime stage ─────────────────────────────────────────────────────────────
FROM ${BASE_CUDA_RUN_CONTAINER}

RUN apt-get update && apt-get install -y \
    libgomp1 \
    libcurl4 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /build/build/bin/llama-server /usr/local/bin/llama-server
COPY --from=builder /build/build/bin/rpc-server   /usr/local/bin/rpc-server

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# MODE=server  → runs llama-server (default)
# MODE=backend → runs rpc-server
ENV MODE=server
ENV PORT=8080

ENTRYPOINT ["/entrypoint.sh"]
