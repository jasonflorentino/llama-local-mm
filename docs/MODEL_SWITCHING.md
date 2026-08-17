# SOP: Switching the active model

This runbook changes the one model used by the existing llama.cpp service. It
does not start a second server or enable router mode.

The service advertises the stable API alias `home-llama` by default. Clients
can keep that model identifier while the underlying Hugging Face GGUF changes.

## Before switching

1. Confirm that no one is generating a response. Restarting the service
   interrupts active responses.
2. Check the current service and model:

   ```bash
   ./status.sh
   ```

3. Confirm adequate disk space. A downloaded model remains in llama.cpp's user
   cache and does not replace the prior download:

   ```bash
   df -h "$HOME"
   ```

4. Use a llama.cpp-compatible Hugging Face GGUF identifier in the form
   `OWNER/REPOSITORY:QUANTIZATION`.

## Switch models

From the repository directory, run:

```bash
./switch-model.sh OWNER/REPOSITORY:QUANTIZATION
```

For Gemma 4 E4B Q4_0:

```bash
./switch-model.sh \
  google/gemma-4-E4B-it-qat-q4_0-gguf:Q4_0
```

The script performs these actions:

1. Saves the current `.env` as `.env.before-model-switch`.
2. Changes only `LLAMA_MODEL` in `.env`.
3. Runs the idempotent `setup.sh`, which restarts the same launchd service.
4. Waits for the download, model load, direct health check, and nginx health
   check to succeed.
5. Restores the previous configuration automatically if setup fails.

The initial download of a large model may take several minutes. Follow progress
from another SSH session:

```bash
tail -F \
  "$HOME/Library/Logs/home-llama/llama-server.out.log" \
  "$HOME/Library/Logs/home-llama/llama-server.err.log"
```

The default startup timeout is 1,800 seconds. Change
`LLAMA_STARTUP_TIMEOUT` in `.env` if the connection requires more time.

## Verify the candidate

Run:

```bash
./status.sh
```

Then open the normal household URL and start a new chat. A new conversation is
best for comparison because continuing an old conversation sends the previous
model's answers to the candidate as history.

Clients configured for the stable `home-llama` alias should not require a model
change. A browser tab left open during the restart may need to be refreshed.

## Return to the previous model

The helper keeps one previous configuration. Swap back with:

```bash
./switch-model.sh --previous
```

Running `--previous` again swaps forward to the other configuration. Only one
previous configuration is retained.

For explicit recovery, inspect `.env.before-model-switch`, copy its desired
`LLAMA_MODEL` value into `.env`, and run:

```bash
./setup.sh
```

## Adopt or discard the candidate

If the candidate is better, no further deployment action is required: `.env`
already contains the active model and launchd will use it after reboot.

If it is unsuitable, run `./switch-model.sh --previous`. Cached GGUF downloads
are deliberately retained so switching back to a previously tested model does
not require another download. Cache cleanup should be a separate, deliberate
maintenance operation.
