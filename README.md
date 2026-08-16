# llama.cpp Home Server

Run `llama.cpp` and its built-in chat UI on a headless Intel Mac, start it
automatically at boot, and expose it to a trusted home network through nginx.

The service layout is:

```text
Browser on LAN → nginx :80 → llama-server 127.0.0.1:8080
                              ├─ built-in chat UI
                              └─ llama.cpp HTTP/OpenAI-compatible API
```

`llama-server` already contains the chat client, so there is no separate Node or
React application to build and deploy.

## What the setup installs

- Homebrew `llama.cpp` and `nginx` packages, if missing.
- A system `LaunchDaemon` that runs `llama-server` as your normal user.
- A root-owned runtime configuration generated from `.env`.
- An nginx virtual host that proxies the UI and API while preserving streaming.
- Persistent logs under `~/Library/Logs/home-llama`.

The daemon binds `llama-server` to loopback only. nginx is the only process
exposed to the LAN.

## Prerequisites

- An Intel Mac running macOS with SSH access.
- Homebrew already installed.
- A user account with `sudo` access.
- Internet access for the initial Homebrew and model downloads.
- A trusted home network.

Check the machine:

```bash
uname -m
system_profiler SPHardwareDataType
system_profiler SPDisplaysDataType
sysctl -n hw.memsize
sw_vers
```

For an Intel Mac, `uname -m` should print `x86_64`.

## Setup

Clone or copy this repository onto the Mac, then:

```bash
cp .env.example .env
$EDITOR .env
./setup.sh
```

The setup script asks for `sudo` when installing the boot service and nginx
configuration. Do not run the entire script as root.

The default model is a conservative 1B Q4 model:

```text
ggml-org/gemma-3-1b-it-GGUF:Q4_K_M
```

This is intended to validate the installation. Once it works, a 3B model will
usually provide better answers; whether that is comfortable depends on the
Mac's CPU and RAM. A 7B/8B model may fit on a 16 GB or larger machine but can be
slow on Intel hardware.

The first startup can take several minutes because `llama-server` downloads the
model into the user's llama.cpp cache.

## DNS and access

Create a local DNS record on your router or DNS server mapping `SERVER_NAME` to
the Mac mini's LAN address. For example:

```text
llama.home.arpa → 192.168.1.42
```

The `.home.arpa` domain is reserved for home-network use and is preferable to
inventing a public-looking domain.

To discover the current LAN address over SSH:

```bash
interface=$(route -n get default | awk '/interface:/{print $2}')
ipconfig getifaddr "$interface"
```

Then open:

```text
http://llama.home.arpa
```

Until DNS exists, use the LAN IP printed by `setup.sh`.

## Configuration

Edit `.env`, then rerun `./setup.sh` to apply changes.

Important settings:

| Variable | Purpose |
| --- | --- |
| `SERVER_NAME` | Local DNS hostname served by nginx |
| `LISTEN_PORT` | LAN-facing nginx port; defaults to `80` |
| `LLAMA_PORT` | Loopback-only llama-server port |
| `LLAMA_MODEL` | Hugging Face GGUF repository and quantization |
| `LLAMA_CTX_SIZE` | Context size; larger values consume more memory |
| `LLAMA_PARALLEL` | Concurrent server slots |
| `LLAMA_DEVICE` | Empty for automatic selection; `none` forces CPU-only |
| `LLAMA_THREADS` | Optional CPU thread override |
| `LLAMA_THREADS_BATCH` | Optional prompt-processing thread override |
| `LLAMA_CACHE_RAM` | Maximum server prompt cache in MiB |
| `LLAMA_GPU_LAYERS` | Optional GPU-offloaded layer count |
| `LLAMA_API_KEY` | Optional API/UI authentication |

For the Macmini8,1 with Intel UHD 630 graphics, use CPU-only inference:

```bash
LLAMA_DEVICE=none
LLAMA_GPU_LAYERS=0
LLAMA_THREADS=6
LLAMA_THREADS_BATCH=12
LLAMA_CACHE_RAM=1024
```

The six generation threads match its physical cores. Twelve batch threads can
use Hyper-Threading while ingesting prompts. The explicit 1 GiB prompt-cache cap
avoids llama-server's much larger default on a 16 GB host.

## Operations

Inspect health and service state:

```bash
./status.sh
```

Restart llama-server:

```bash
sudo launchctl kickstart -k system/com.home-llama.server
```

Follow logs:

```bash
tail -F \
  "$HOME/Library/Logs/home-llama/llama-server.out.log" \
  "$HOME/Library/Logs/home-llama/llama-server.err.log"
```

Validate and restart nginx:

```bash
sudo "$(command -v nginx)" -t
sudo "$(command -v brew)" services restart nginx
```

Upgrade llama.cpp:

```bash
brew update
brew upgrade llama.cpp
sudo launchctl kickstart -k system/com.home-llama.server
```

## Uninstall

```bash
./uninstall.sh
```

This removes the launchd service, its generated runtime configuration, and the
nginx virtual host. It deliberately leaves the model cache, logs, `.env`,
Homebrew packages, and repository intact.

## Security

- Do not forward the nginx port from your router to the public internet.
- Treat the web UI as available to every device on the LAN unless you set
  `LLAMA_API_KEY` or add authentication/TLS at nginx.
- Do not enable llama.cpp's `--agent` or `--tools` options on an untrusted
  network; they can expose filesystem or shell capabilities.
- The optional API key protects llama.cpp routes, but plain HTTP does not
  encrypt it. For an untrusted network, add HTTPS or access the loopback service
  through an SSH tunnel instead.

## Troubleshooting

If llama-server does not become healthy:

```bash
tail -n 100 "$HOME/Library/Logs/home-llama/llama-server.err.log"
sudo launchctl print system/com.home-llama.server
```

If nginx is unavailable:

```bash
sudo nginx -t
sudo brew services list
lsof -nP -iTCP -sTCP:LISTEN
```

If nginx cannot bind port 80, another service is probably using it. Change
`LISTEN_PORT`, or stop the conflicting service, then rerun `./setup.sh`.

If wireless clients cannot connect to the wired Mac, check the macOS firewall
and whether the router has client/AP isolation enabled.
