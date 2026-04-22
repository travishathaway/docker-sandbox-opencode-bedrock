# Attempted: Credential Refresh via Stock OpenCode Sandbox

This document records a full investigation into replacing the custom Docker image
in this repo with the stock `docker/sandbox-templates:opencode` image, using a
host-side `refresh.sh` script to push AWS SSO credentials into the running
sandbox. The approach was ultimately abandoned. This document explains why, so
the work is not repeated.

## Goal

Use `sbx run opencode` (no custom image) and refresh short-lived AWS SSO
credentials into the sandbox on demand, without restarting it.

## Why the stock image was appealing

- No custom image to build, publish, or maintain
- Uses Docker's official OpenCode sandbox directly
- A periodic `refresh.sh` script aligned well with the SSO token expiry cycle

## What was tried

### Step 1: `/etc/sandbox-persistent.sh` via `sbx exec`

The Docker Sandbox FAQ documents `/etc/sandbox-persistent.sh` as the supported
mechanism for injecting custom environment variables into a sandbox:

> Variables in `/etc/sandbox-persistent.sh` are sourced automatically when bash
> runs inside the sandbox, including interactive sessions and agents started
> with `sbx run`.

`refresh.sh` used `aws configure export-credentials --profile <profile> --format env-no-export`
on the host to extract fresh STS credentials, then wrote all four variables into
the sandbox via `sbx exec -d`:

```
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
AWS_SESSION_TOKEN
AWS_REGION
```

**Result:** OpenCode still reported `Could not load credentials from any providers`.

---

### Step 2: `/etc/environment` in addition to `/etc/sandbox-persistent.sh`

Hypothesis: `sbx run opencode` launches the OpenCode process directly (not via a
login shell), so `/etc/sandbox-persistent.sh` is never sourced before the process
starts. `/etc/environment` is read by PAM at process startup and does not require
a shell.

`refresh.sh` was updated to write credentials to both files.

**Result:** Same error. No change.

---

### Step 3: Inspect the running process environment directly

The `/proc` filesystem reveals the actual environment of the live opencode
process, bypassing all shell and file sourcing questions:

```bash
sbx exec -it <sandbox-name> bash -c \
  "cat /proc/\$(pgrep -f opencode | head -1)/environ | tr '\0' '\n' | grep AWS"
```

**Output:**
```
AWS_ACCESS_KEY_ID=proxy-managed
```

This was the key finding. The `sbx` proxy pre-injects `AWS_ACCESS_KEY_ID=proxy-managed`
into the OpenCode process environment at launch. This happens before PAM, before
any shell sourcing — it wins unconditionally over anything written to
`/etc/environment` or `/etc/sandbox-persistent.sh`.

`proxy-managed` is a sentinel placeholder. The proxy is designed to replace it
with real credentials sourced from `sbx secret`. Since no `sbx secret set -g aws`
had been run, the proxy had no real values and passed the placeholder through as-is.
The AWS SDK then rejected it.

---

### Step 4: `sbx secret set` to feed credentials through the proxy

The proxy owns `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`. The only way to
give it real values is through `sbx secret set`.

`refresh.sh` was updated to pipe credentials to the proxy:

```bash
echo "${KEY_ID}:${SECRET}" | sbx secret set "$SANDBOX" aws
```

`AWS_SESSION_TOKEN` and `AWS_REGION` were still written to
`/etc/sandbox-persistent.sh`, since the proxy does not manage those variables.

**Result:** `sbx secret set` ran without error. After restarting the sandbox,
`/proc` still showed `AWS_ACCESS_KEY_ID=proxy-managed`.

---

## Why it cannot work

The `sbx` credential proxy is designed for **static, long-lived API keys**. For
the `aws` service it only manages two variables:

| Variable | Managed by proxy |
|---|---|
| `AWS_ACCESS_KEY_ID` | Yes |
| `AWS_SECRET_ACCESS_KEY` | Yes |
| `AWS_SESSION_TOKEN` | **No** |
| `AWS_REGION` | No |

AWS SSO issues **short-lived STS credentials** that always include
`AWS_SESSION_TOKEN`. Without it, the `AWS_ACCESS_KEY_ID` and
`AWS_SECRET_ACCESS_KEY` values are rejected by AWS with a signature error —
even if the proxy were injecting them correctly.

There is no supported way to get `AWS_SESSION_TOKEN` through the proxy. The
`/etc/sandbox-persistent.sh` path for that variable is blocked by the proxy
overriding the AWS key variables first, breaking the full credential set.

Additionally, the `sbx secret set -g aws` global form only applies at sandbox
**creation** time. The sandbox-scoped form is documented to take effect
immediately, but in practice did not update the injected value in the running
process.

## Conclusion

The stock `docker/sandbox-templates:opencode` sandbox proxy is incompatible with
AWS SSO credentials. The proxy cannot be bypassed for `AWS_*` variables, and it
does not support `AWS_SESSION_TOKEN`.

**The custom image approach in this repo (mounting `~/.aws:ro` via `sbx run` and
symlinking it into `$HOME` via `entrypoint.sh`) is the correct solution for AWS
SSO.** It works because it bypasses the proxy entirely by delivering credentials
through the filesystem rather than environment variables, using a read-only host
volume mount that the proxy has no visibility into.

## Artefacts from this investigation

- `refresh.sh` — left in the repo as a reference. It correctly extracts SSO
  credentials from the host via `aws configure export-credentials` and was a
  sound approach up until the proxy wall was hit. Could be repurposed if Docker
  ever adds `AWS_SESSION_TOKEN` support to the proxy.
- `opencode.json` — project-level OpenCode config template. Documented finding:
  the OpenCode docs state that **config file options take precedence over
  environment variables** for the `amazon-bedrock` provider. A `profile` key in
  `opencode.json` will override env var credentials. The file in this repo
  intentionally omits `profile` for this reason.
