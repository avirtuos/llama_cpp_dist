ARG UBUNTU_VERSION=22.04
ARG CUDA_VERSION=12.8.0
ARG BASE_CUDA_DEV_CONTAINER=nvidia/cuda:${CUDA_VERSION}-devel-ubuntu${UBUNTU_VERSION}
ARG BASE_CUDA_RUN_CONTAINER=nvidia/cuda:${CUDA_VERSION}-runtime-ubuntu${UBUNTU_VERSION}

# Default targets the DGX Spark GB10 (Blackwell sm_100).
# Pass --build-arg CMAKE_CUDA_ARCHITECTURES=native for an optimized single-GPU local build.
ARG CMAKE_CUDA_ARCHITECTURES=100

# ── Build stage ──────────────────────────────────────────────────────────────
FROM ${BASE_CUDA_DEV_CONTAINER} AS builder

ARG CMAKE_CUDA_ARCHITECTURES

# Explicitly ensure nvcc is in PATH — ARG reset can drop ENV from the base image
ENV PATH=/usr/local/cuda/bin:${PATH}
# Expose the CUDA driver stub so the linker can resolve Driver API symbols
# (cuGetErrorString etc.) at build time. The real libcuda.so.1 comes from
# the NVIDIA driver at runtime via the container runtime.
ENV LIBRARY_PATH=/usr/local/cuda/lib64/stubs:${LIBRARY_PATH}

RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    libssl-dev \
    libcurl4-openssl-dev \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s /usr/local/cuda/lib64/stubs/libcuda.so \
             /usr/local/cuda/lib64/stubs/libcuda.so.1

WORKDIR /build
RUN git clone --depth=1 https://github.com/ggml-org/llama.cpp .

RUN cmake -B build \
    -DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc \
    -DGGML_CUDA=ON \
    -DGGML_RPC=ON \
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
