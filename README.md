# llamma_cpp_dist

Docker image for distributed [llama.cpp](https://github.com/ggml-org/llama.cpp) inference over RPC, compiled with CUDA support. Published to Docker Hub as [`avirtuos/llama_cpp_dist`](https://hub.docker.com/r/avirtuos/llama_cpp_dist).

## What This Image Does

The image ships two binaries selected by the `MODE` environment variable:

| `MODE` | Binary | Role |
|--------|--------|------|
| `server` (default) | `llama-server` | Serves an OpenAI-compatible API, distributes model layers to RPC backends |
| `backend` | `rpc-server` | Contributes GPU memory/compute to a remote `llama-server` over RPC |

**RPC architecture** — a single `llama-server` instance connects to one or more `rpc-server` instances over TCP, distributing model layers across all GPUs so models that exceed a single GPU's VRAM can still be loaded.

```
  Open WebUI  ──►  spark01 (llama-server, port 8080)
                        │
                        │ RPC over TCP port 50052
                        │
                   spark02 (rpc-server, port 50052)
```

## Quick Start

Pull the image on **both nodes**:

```bash
docker pull avirtuos/llama_cpp_dist:latest
```

**Step 1 — Deploy the RPC backend stack on spark02 (deploy first)**

From the Portainer UI (`https://10.0.26.61:9443`), switch to the **spark02** environment, go to **Stacks → Add Stack**, name it `llama-rpc-backend`, and paste:

```yaml
services:
  rpc-backend:
    image: avirtuos/llama_cpp_dist:latest
    network_mode: host
    runtime: nvidia
    volumes:
      - /mnt/hf-cache:/root/.cache/llama.cpp
    environment:
      - NVIDIA_VISIBLE_DEVICES=all
      - MODE=backend
      - PORT=50052
    restart: unless-stopped
```

**Step 2 — Deploy the llama-server stack on spark01 (deploy second)**

Switch to the **spark01** environment, go to **Stacks → Add Stack**, name it `llama-gpt-oss`, and paste:

```yaml
services:
  llama-server:
    image: avirtuos/llama_cpp_dist:latest
    network_mode: host
    runtime: nvidia
    volumes:
      - /mnt/hf-cache:/root/.cache/llama.cpp
    environment:
      - NVIDIA_VISIBLE_DEVICES=all
      - MODE=server
      - HF_TOKEN=your_token_here
    command: >
      -hf ggml-org/gpt-oss-120b-GGUF
      --rpc 10.0.22.253:50052
      --ctx-size 0
      --jinja
      -ub 2048
      -b 2048
      --host 0.0.0.0
      --port 8080
    restart: unless-stopped
```

> **Note on HF_TOKEN**: `ggml-org/gpt-oss-120b-GGUF` is a gated model. Visit https://huggingface.co/ggml-org/gpt-oss-120b-GGUF, accept the license, then generate a token at https://huggingface.co/settings/tokens and set it above.

> **Note on model cache**: llama.cpp's `-hf` flag downloads models to `/root/.cache/llama.cpp/` (not the HuggingFace Python cache at `/root/.cache/huggingface`). The volume mount above ensures downloaded models persist across container restarts.

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
5. Copy the token immediately (it won't be shown again)

**Adding the secrets to GitHub:**
1. Go to your repository on GitHub
2. Click **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret** and add `DOCKERHUB_USERNAME` (your Docker Hub username)
4. Click **New repository secret** again and add `DOCKERHUB_TOKEN` (the token from step 5 above)

## Image Tags

| Event | Tags produced |
|-------|--------------|
| Push to `main` | `latest`, `sha-<short>` |
| Push `v1.2.3` tag | `1.2.3`, `1.2`, `1`, `sha-<short>` |
| Pull request to `main` | Build only — no push |
