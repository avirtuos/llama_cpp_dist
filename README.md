# llamma_cpp_dist

Docker image for distributed [llama.cpp](https://github.com/ggml-org/llama.cpp) inference over RPC, compiled with CUDA support. Published to Docker Hub as [`avirtuos/llamma_cpp_dist`](https://hub.docker.com/r/avirtuos/llamma_cpp_dist).

## What This Image Does

The image ships two binaries selected by the `MODE` environment variable:

| `MODE` | Binary | Role |
|--------|--------|------|
| `server` (default) | `llama-server` | Serves an OpenAI-compatible API, distributes model layers to RPC backends |
| `backend` | `rpc-server` | Contributes GPU memory/compute to a remote `llama-server` over RPC |

**RPC architecture** — a single `llama-server` instance connects to one or more `rpc-server` instances over TCP, distributing model layers across all GPUs so models that exceed a single GPU's VRAM can still be loaded.

```
  Client  ──►  llama-server (server node, port 8080)
                    │
                    │ RPC over TCP port 50052
                    │
               rpc-server (backend node, port 50052)
```

## Quick Start

```bash
docker pull avirtuos/llamma_cpp_dist:latest
```

**Run as a server** (serves OpenAI-compatible API on port 8080):

```bash
docker run --gpus all --network host \
  -e MODE=server \
  -e HF_TOKEN=your_token_here \
  -v /mnt/hf-cache:/root/.cache/huggingface \
  avirtuos/llamma_cpp_dist:latest \
  -hf ggml-org/gpt-oss-120b-GGUF \
  --rpc 192.168.1.2:50052 \
  --ctx-size 0 \
  --host 0.0.0.0 \
  --port 8080
```

**Run as a backend** (RPC backend on port 50052):

```bash
docker run --gpus all --network host \
  -e MODE=backend \
  -e PORT=50052 \
  avirtuos/llamma_cpp_dist:latest
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MODE` | `server` | `server` runs `llama-server`; `backend` runs `rpc-server` |
| `PORT` | `8080` (`server`) / `50052` (`backend`) | Listening port (backend mode uses `PORT` for `rpc-server --port`) |

Additional `llama-server` flags (e.g. `-hf`, `--rpc`, `--ctx-size`) are passed as command arguments after the image name.

## Building Locally

```bash
git clone https://github.com/avirtuos/llamma_dist.git
cd llamma_dist

# Default build — targets Ampere, Ada, Hopper, and Blackwell
docker build -t llamma_cpp_dist:local .

# Optimized for the exact GPU on your machine (requires GPU at build time)
docker build --build-arg CMAKE_CUDA_ARCHITECTURES=native -t llamma_cpp_dist:local .
```

The build clones llama.cpp and compiles from source — expect 10–20 minutes.

## CI/CD — Required GitHub Secrets

To enable automatic publishing to Docker Hub, configure the following secrets in your GitHub repository under **Settings → Secrets and variables → Actions**:

| Secret | Description |
|--------|-------------|
| `DOCKERHUB_USERNAME` | Your Docker Hub username (e.g. `avirtuos`) |
| `DOCKERHUB_TOKEN` | A Docker Hub access token with **Read & Write** scope |

**Creating a Docker Hub access token:**
1. Log in to [hub.docker.com](https://hub.docker.com)
2. Click your avatar → **Account Settings**
3. Go to **Security** → **Personal access tokens**
4. Click **Generate new token**, give it a description (e.g. `github-actions`), set scope to **Read & Write**, and click **Generate**
5. Copy the token immediately (it won't be shown again) and add it as the `DOCKERHUB_TOKEN` secret in GitHub

## Image Tags

| Event | Tags produced |
|-------|--------------|
| Push to `main` | `latest`, `sha-<short>` |
| Push `v1.2.3` tag | `1.2.3`, `1.2`, `1`, `sha-<short>` |
| Pull request to `main` | Build only — no push |
