# TODO.AI.md

## Found, not fixed — healthcheck reports "healthy" before HTTP port reliably reachable after `docker restart`

Found via a structured beta-test pass (`beta-tester` agent) against `forgejo-test:local`
built and run locally after today's Dockerfile/act_runner fixes, to verify prod-readiness.

- Repro: `docker restart` the container, poll `docker inspect --format
  '{{.State.Health.Status}}'` until `healthy`, then immediately issue an external HTTP
  request (e.g. `curl http://localhost:18080/api/v1/version`) — the very first request
  right after the healthy transition returned `Recv failure: Connection reset by peer`,
  even though the internal `forgejo web` process was already running per `ps aux`. A retry
  seconds later succeeded normally.
- Likely cause: a short window where the internal process is up (satisfying whatever the
  healthcheck probes internally) but the Docker userland-proxy/port-publish path for
  `-p 18080:80` hasn't stabilized yet, or the health check races the actual listener bind.
- Impact: anything that gates traffic on Docker's health status (`docker-compose`
  `depends_on: condition: service_healthy`, orchestrator health gates) could send requests
  into this gap and get a connection reset instead of a retry-able error. Self-resolves
  within seconds; no data loss observed.
- Severity: Medium. Not fixed here — needs a decision on whether to add a stabilization
  delay to the healthcheck script or have it check the published port itself rather than an
  internal probe; out of scope for the commit that prompted this beta test.

## Found, not verified — `git push` (HTTP + SSH) not exercised by beta test

The beta-test agent verified `git clone` over both HTTP basic-auth and SSH (before and
after restart) but could not verify `git push` — its own commit-safety guard
(`no-subagent-commit.sh`) blocks any Bash command containing `git commit`/`git push`, even
against an unrelated scratch repo. Read-path (clone) confirmed working; write-path (push)
still unverified. Low severity — recommend a push test the next time this image is
verified, from the main session rather than a subagent.

## Found, informational only — `GET /api/v1/admin/runners` returns 404 for basic-auth admin

Found during the same beta-test pass. Not confirmed as a defect — may simply be an
unsupported/nonexistent API path in Forgejo 16.0.3 rather than a permissions bug; the
README doesn't document this specific admin API endpoint. Runner functionality itself
(registration, daemon startup, job labels) was independently confirmed working via logs and
process inspection, so this is flagged only for awareness, not as a known-broken feature.

## Found, not fixed — stale `__copy_templates`/`DEFAULT_TEMPLATE_DIR` calls in functions/entrypoint.sh

Found incidentally while running AI.md PART 8's dead-reference gate ("No `__copy_templates`
calls remain (retired with `DEFAULT_TEMPLATE_DIR`)") before committing an unrelated set of
fixes.

- `rootfs/usr/local/etc/docker/functions/entrypoint.sh` still defines `__copy_templates`
  (line 650) and calls it at lines 457, 459, 512, 519 — the exact pattern AI.md PART 8
  documents as retired alongside `DEFAULT_TEMPLATE_DIR`.
- `functions/entrypoint.sh` is a `gen-dockerfile`-generated file (per AI.md's ownership
  rules) — per rule 2, this must be fixed in the upstream `gen-dockerfile` template and then
  regenerated, not hand-edited in this repo. Not fixed here — out of scope for the current
  commit and requires the upstream template repo, not this one.

## App-breaking bug fixed — runner daemon cache secret key wrong (build/test cycle)

Found while functionally testing the built image: after registration succeeded, the
`act_runner daemon` process still logged `A cache secret must be specified to use an
external cache server, cache will be disabled`, even though `ps aux` confirmed it was
launched with `--config /config/act_runner/runners-cache.yaml` and that file contained a
non-empty secret.

- `rootfs/usr/local/bin/start-runners` (heredoc generating `runners-cache.yaml`, line 112):
  used `external_secret:` under `cache:`. Verified via `strings /usr/local/bin/act_runner`
  on the actual binary that this act_runner v13.1.0's embedded config schema uses `secret:`
  for the client/daemon side too — `external_secret` is not a recognized key anywhere in
  this binary version. Fixed to `secret: '${RUNNER_CACHE_SECRET}'`.
- `rootfs/tmp/etc/act_runner/default_config.yaml` (`cache:` block, line 71): same wrong
  key, same fix — `external_secret:` → `secret: 'REPLACE_RUNNER_CACHE_SECRET'`. This is the
  template copied to `/config/act_runner/forgejo/act_runner.yaml` at container startup.

## App-breaking bug fixed — runner registration token truncated by regex (build/test cycle)

Found while functionally testing the built image: act_runner failed to register with
`invalid_argument: runner registration token not found` even though a token was
generated and written to `/config/act_runner/tokens/system`.

- `rootfs/usr/local/etc/docker/init.d/zz-act_runner.sh` (`__gen_auth_token`, line 146):
  `forgejo actions generate-runner-token` returns a token containing hyphens (verified
  empirically, e.g. `FREHhNzKSoKU3KLpB3SwHLX1O1PvTAJGTZn2rmf--MR`), but the extraction
  regex `grep -oE '[A-Za-z0-9]{20,}'` only matches alnum runs, so `tail -n1` returned
  just the alnum prefix and silently dropped the `--MR` suffix — writing a truncated,
  invalid token that Forgejo's API correctly rejects on registration. Fixed the regex to
  `[A-Za-z0-9_-]{20,}` so the full token is captured.

## App-breaking bug fixed — cache_server.yaml wrong config key (build/test cycle)

Found while functionally testing the built image: `act_runner cache-server` exited
immediately with `no cache secret was specified, exiting.` even though a secret was
generated and injected.

- `rootfs/tmp/etc/act_runner/cache_server.yaml`: used `external_secret` under `cache:`,
  but `act_runner cache-server`'s config loader only recognizes `secret` (matches the
  CLI's `--secret` flag; `external_secret` is the client-side key used in
  `default_config.yaml`'s `cache:` block to point a *runner* at an *external* cache
  server — not the key the cache-server itself reads). Verified empirically: same config
  with `secret:` starts and runs cleanly; with `external_secret:` it exits immediately.
  Fixed to `secret: 'REPLACE_RUNNER_CACHE_SECRET'`.

## App-breaking bug fixed — sshd_config AllowUsers mismatch (gitea→forgejo migration)

Found incidentally while sweeping for remaining "gitea" references during the forgejo rename.

- `rootfs/tmp/etc/ssh/sshd_config`: `AllowUsers gitea` referenced a system account that is never
  created — `08-forgejo.sh` sets `SERVICE_USER="git"`, and no script anywhere creates a `gitea`
  user. This bug predates the rename (the same mismatch existed in the gitea version) and would
  have silently blocked all git-over-SSH logins. Fixed to `AllowUsers git`.

## Lint cleanup done — UUOC fixed (start-runners)

Verified clean by `script-lint` agent after fix.

- `rootfs/usr/local/bin/start-runners`: line 24 UUOC (`echo | grep -q '://'`) replaced with
  `[[ "$SERVER_ADDRESS" != *"://"* ]]`; grep call removed entirely so the missing `--` no longer
  applies.

## Lint cleanup done — version stamp and grep -- fixed (zz-act_runner.sh)

Verified clean by `script-lint` agent after fix.

- `rootfs/usr/local/etc/docker/init.d/zz-act_runner.sh`: added `VERSION="202608031200-git"`
  matching the existing `##@Version` header; added `--` before the pattern argument on all 15 grep
  invocations in the file (not just the subset originally enumerated); quoted the bare `grep`
  pattern at the former line 544 (now `grep -v -- 'grep'`).

## Lint cleanup done — line-length violation fixed (start-runners)

- `rootfs/usr/local/bin/start-runners`: the 781-char `RUNNER_LABELS="${RUNNER_LABELS:-...}"`
  default literal was replaced with a `_default_runner_labels` array joined via `IFS=,`, only
  applied when `RUNNER_LABELS` is unset. Verified with `bash -n` and a line-length scan (no line
  exceeds 180 chars).

## App-breaking bug fixed — DEBUGGER guard pattern under set -e (functions/entrypoint.sh)

Needs syncing back to the upstream template in `casjay-dotfiles/scripts` per the Docker Template
Update Runbook in AI.md — `functions/entrypoint.sh` is normally regenerated, not hand-edited.

- 26x occurrences of `[ "$DEBUGGER" = "on" ] && echo/printf/__service_banner "..."` used as a bare
  statement: under `set -e`, this aborts the whole script silently whenever `$DEBUGGER` != "on"
  (the default). This was the root cause of the container dying immediately after printing only
  the startup banner. Fixed by appending `|| true` to all 26 occurrences.

## App-breaking bug fixed — __random_password() SIGPIPE (functions/entrypoint.sh)

Needs syncing back to the upstream template in `casjay-dotfiles/scripts` per the Docker Template
Update Runbook in AI.md — `functions/entrypoint.sh` is normally regenerated, not hand-edited.

- `__random_password()` (~line 333): `tr | head -c` pipeline died under `set -eo pipefail` on
  SIGPIPE. Fixed by wrapping in `{ ... } || true`.

## App-breaking bug fixed — __format_variables() whitespace-only input (functions/entrypoint.sh)

Needs syncing back to the upstream template per AI.md's runbook.

- `__format_variables()` (~line 187): `printf '%s\n' $input | sort -Ru | tr '\n' ' '` always
  emits at least one line even when `$input` word-splits to zero words (whitespace-only), because
  `printf` with a format containing `%s` runs once even with no args. This made `ENV_PORTS` /
  `WEB_SERVER_PORTS` resolve to a single space `" "` instead of empty when no port env vars were
  set, which made `SERVICE_PORT` in `08-gitea.sh` become `" "` — passing the `-n` test but
  rendering as an empty `--port` arg to `gitea web`, which broke gitea's CLI argument parsing
  entirely (`Command error: unknown command: /config/gitea/app.ini`). Fixed by replacing the
  `[ -z "$input" ]` check with `[[ "$input" =~ [^[:space:]] ]] || return 0`.

## App-breaking bug fixed — missing /config/env directory (bin/entrypoint.sh)

- `/config/env` directory was never explicitly created. It only came into existence as a side
  effect of `__create_env_file()` (functions/entrypoint.sh) copying
  `/usr/local/etc/docker/env/default.sample` into it — but that sample file/dir does not exist in
  this image's rootfs, so `__create_env_file()` returns early (line 960) without creating the
  directory. `05-dockerd.sh`'s `__create_service_env()` then fails writing
  `/config/env/docker.local.sh` directly (`cat <<'EOF' >"/config/env/....local.sh"`, no `tee`
  suppression) with `No such file or directory`; `zz-act_runner.sh` hits the same error writing
  `/config/env/act_runner.local.sh`. Fixed by adding
  `mkdir -p "/config/env" 2>/dev/null || true` alongside the other `/config/*` directory creation
  lines (~line 241) in `rootfs/usr/local/bin/entrypoint.sh`. Needs syncing to the upstream
  template per AI.md's runbook.

## OCI label cleanup done — forbidden labels removed from Dockerfile

- Removed `org.opencontainers.image.base.name` (belongs on the base image, not the app image) and
  `org.opencontainers.image.schema-version` (non-spec, redundant with `version`).
- Removed the duplicate `org.opencontainers.image.authors="${LICENSE}"` line and duplicate
  `org.opencontainers.image.source="https://docker.io/..."` line; the license value now correctly
  populates the (previously missing) `org.opencontainers.image.licenses` label per AI.md's OCI
  label standard (lines 58-87), and `source` keeps the single github.com URL.

## App-breaking bug fixed — act_runner init.d hang + duplicate runner registration (zz-act_runner.sh)

Needs syncing back to the upstream template in `casjay-dotfiles/scripts` per the Docker Template
Update Runbook in AI.md — the outer hooks (`__post_execute`, `__run_start_script`) are normally
generated, not hand-edited, but this repo's app-specific runner logic already lives inline in
them rather than in the `*_local()` stubs, so the fix was applied in place.

- Root cause of the hang: because `EXEC_CMD_BIN=''` for this service, `__run_start_script`
  (called at the script's tail) internally calls `__post_execute` synchronously through
  `__post_execute | tee -p -a "/data/logs/init.txt"`. Inside `__post_execute`'s own backgrounded
  subshell, `/usr/local/bin/start-runners &` was launched without redirecting its stdout/stderr,
  so it (and the long-running `act_runner daemon` processes it `exec`s, which never exit)
  inherited the write end of that `tee` pipe. Since that write end never closed, `tee` never saw
  EOF, so it never exited, so `__run_start_script` never returned, so `__start_init_scripts`'s
  `( source "$init" )` for this script never completed — the init.d loop hung forever after all
  services were actually up, and `/data/logs/start.log`'s final `printf` (the completion marker)
  was never reached. Fixed by redirecting `start-runners`'s stdout/stderr to
  `"$LOG_DIR/runners.log"` at its invocation site instead of inheriting the pipe.
- The script also called `__post_execute` a second time explicitly
  (`__post_execute ... | tee ... &` near the end of the script), duplicating the call
  `__run_start_script` already makes via its empty-`EXEC_CMD_BIN` branch. Removed the redundant
  explicit call.
- The script additionally registered and started a hardcoded, always-on single runner named
  `"gitea"` (in `__run_pre_execute_checks` and `__post_execute`) independent of and in addition
  to the `RUNNERS_START`-driven runners from `start-runners` — so `RUNNERS_START=2` produced 3
  registered runners (`gitea`, `runner-1`, `runner-2`) instead of 2. Removed both the legacy
  registration block and its matching daemon-start block; `start-runners` (already idempotent
  per-runner via its `.runner`-file check) is now the sole runner registration/startup path.
- Verified with `bash -n` and a live rebuild/retest: the init.d loop now completes and
  `/data/logs/start.log` gets its completion marker; only `runner-1`/`runner-2` are registered
  (no `gitea` runner).

## App-breaking bug fixed — act_runner registered against wrong/unreachable IP (zz-act_runner.sh)

Needs syncing back to the upstream template per AI.md's runbook (same file/hooks as above).

- `RUNNER_IP_ADDRESS` defaulted to `$IP4_ADDRESS` (the container's externally-detected IP,
  captured once very early in `bin/entrypoint.sh` via `__get_ip4`). In live testing this value
  did not match the container's actual `eth0` address by the time `act_runner daemon` tried to
  connect, causing every runner to fail its first RPC with `dial tcp <ip>:80: connect: no route
  to host` and exit immediately (act_runner does not retry a failed initial connection). Since
  act_runner registers against gitea running in the very same container/network namespace, the
  detected external IP was never the right thing to use. Fixed by defaulting `RUNNER_IP_ADDRESS`
  to `127.0.0.1` instead (still overridable via the `RUNNER_IP_ADDRESS` env var).
- Verified live: after the fix, `curl http://127.0.0.1/` inside the container succeeds
  immediately. A first retest still showed runners connecting to `172.17.0.2:80`, but this
  was a false alarm caused by stale test volumes: a previous test run's `.runner`
  registration files (with the old baked-in address) were still present, and
  `__register_runner`'s idempotency check correctly skipped re-registering over them. After
  fully removing the test volumes and starting a genuinely fresh container, runner
  registration and connectivity succeeded (`Runner registered successfully.` /
  `declare successfully` for both `runner-1` and `runner-2`, no connection errors).

## App-breaking bug fixed — cache-server fd leak hangs init.d loop (zz-act_runner.sh)

Needs syncing back to the upstream template per AI.md's runbook (same file/hooks as above).

- Same fd-leak class as the `start-runners` hang fixed above, but for
  `act_runner cache-server`: `act_runner cache-server --config "$CACHE_CONFIG_FILE"
  2>>/dev/stderr >>"$CACHE_LOG_FILE" &` used `2>>/dev/stderr`, which duplicates the
  process's *current* stderr fd — at that point in `__post_execute`'s backgrounded
  subshell, still the write end of the `tee -p -a "/data/logs/init.txt"` pipe used by the
  synchronous `__post_execute` call in `__run_start_script`. Since `cache-server` is a
  long-running daemon that never exits, that pipe's write end never closed, so `tee` never
  saw EOF, hanging `__run_start_script` (and therefore the whole init.d loop) forever even
  though dockerd/gitea/act_runner/cache-server were all actually up and working. Fixed by
  redirecting to `"$CACHE_LOG_FILE" 2>&1` instead of `/dev/stderr`.
- The redirect fix alone did not fully resolve the hang: the subshell launching
  `start-runners`/`cache-server` (the left side of `__post_execute`'s pipe to
  `tee -p -a /data/logs/init.txt`) was still observed blocked in `do_wait` on its
  long-running child even with output redirected to a real file, preventing the pipe from
  ever seeing EOF. Added an explicit `disown "$!"` immediately after each background launch
  (`act_runner cache-server` and `/usr/local/bin/start-runners`) to fully detach them from
  the subshell's job table.
- Verified live on a genuinely fresh container (volumes removed first): `/data/logs/start.log`
  now gets its completion marker, no orphaned `tee -p -a /data/logs/init.txt` processes
  remain, and both `runner-1`/`runner-2` register and declare successfully against gitea
  (`runners.log` shows `Runner registered successfully.` and `declare successfully` for
  both, no connection errors).

## App-breaking bug fixed — dockerd fails to restart under rapid restart cycling (05-dockerd.sh)

Found while directly testing the user's "restart container many times" requirement with a rapid
4x-restart loop.

- `docker restart` reuses the same container filesystem (unlike a fresh `run`), so
  `/tmp/docker.pid` from the previous dockerd instance survives the restart. The PID namespace
  itself resets on every restart, so the low PID number written into that file (e.g. `461`) can
  coincidentally be reused by an unrelated early-boot process in the new namespace. dockerd's own
  startup check saw `/proc/<pid>` exist and refused to start: `failed to start daemon, ensure
  docker is not running or delete /tmp/docker.pid: process with PID 461 is still running`.
- Observed impact: `05-dockerd.sh` logged `❌ Service dockerd failed to start - check logs`, but
  gitea and act_runner still reported starting successfully; the entrypoint logged
  `⚠️ Warning: 1 critical service(s) reported failures` / `ℹ️ Continuing with 1 failure(s) -
  container may still be functional` and kept going in a degraded state, then the whole container
  crashed anyway roughly 2 minutes later (`ExitCode=1`).
- Fixed by removing `/tmp/docker.pid` unconditionally at the top of `__run_pre_execute_checks` in
  `05-dockerd.sh`, before dockerd is started. This init script is the sole owner of the dockerd
  lifecycle (a separate real overlap-guard already exists via `SERVICE_PID_FILE`), so clearing
  docker's own pidfile before every start attempt is safe.
- Verified live on a rebuilt image: no `failed to start daemon` / stale-pidfile error appeared in
  the logs across either a 3x normally-paced restart loop or a 4x rapid back-to-back restart burst
  (see the verification note on the PID-reuse fix below — both fixes were tested together in the
  same runs).

## App-breaking bug fixed — PID-reuse false positive kills container after restart (entrypoint.sh, functions/entrypoint.sh)

Found and fixed immediately after the dockerd stale-pidfile fix above, while retesting restart
robustness on the rebuilt image. Same root bug class (a PID recorded in a file that persists
across `docker restart` gets coincidentally reused by an unrelated process once the PID namespace
resets), but hitting two different guards this time, one of which actively took down the whole
container:

- `functions/entrypoint.sh`'s `__no_exit()`: guarded re-entry with `[ -f /run/.no_exit.pid ] &&
  kill -0 "$no_exit_pid"`. After a restart, an unrelated early-boot process could reuse that old
  PID number, making the check wrongly believe the monitor loop was already running. `__no_exit`
  then `return`ed 0 instead of `exec`ing the actual monitor loop, so `bin/entrypoint.sh` fell
  straight through to `exit $?` — the whole entrypoint process exited cleanly (`ExitCode=0`),
  killing the container roughly 2 minutes after a normal, correctly-paced restart, well after
  dockerd/gitea/act_runner had all logged successful starts. This is almost certainly the actual
  root cause behind earlier restart-loop crashes previously attributed only to the dockerd
  stale-pidfile bug.
- `bin/entrypoint.sh`'s `ENTRYPOINT_PID_FILE` check (~line 433) has the identical hazard in the
  opposite direction: a false-positive "still alive" match sets `START_SERVICES=no`, which would
  silently skip `__start_init_scripts` entirely on a genuine restart (not observed in this test run,
  but reachable by the same mechanism).
- Fixed both by requiring the live PID's own `/proc/<pid>/cmdline` to actually match the expected
  process, not just `kill -0` succeeding: `__no_exit`'s exec'd monitor loop now embeds a
  `__no_exit_monitor_loop` marker comment in its own `bash -c` command text (visible in its own
  cmdline), and the re-check greps for it; `ENTRYPOINT_PID_FILE`'s check greps the candidate PID's
  cmdline for `entrypoint.sh`.
- Verified live on a rebuilt image (fresh volumes): a 3x normally-paced restart loop (each
  followed by a 90s post-init settle, well past the previously-observed ~2min crash window) and a
  4x rapid back-to-back restart burst (3s apart, no waiting for init between them) both completed
  with the container remaining `running`/`ExitCode=0` throughout — no clean-exit crash, and no
  `failed to start daemon ... still running` dockerd error in the logs. Runner UUIDs for all 5
  registered runners were identical before and after both test sequences (`/config/act_runner/reg/`
  still holds exactly 5 directories, no duplicates), confirming the "same id, not new" requirement
  holds even under rapid restart cycling.

## Config cleanup done — deprecated `[webhook].ALLOWED_HOST_LIST` moved to `[security]` (rootfs/tmp/etc/gitea/app.ini)

- Every `gitea admin user create` (and, by extension, every gitea startup) logged:
  `[E] Deprecation: config option [webhook].ALLOWED_HOST_LIST present, please use
  [security].ALLOWED_HOST_LIST instead because this fallback will be/has been removed in v28.0.0`.
- Root cause: the shipped `app.ini` template set `ALLOWED_HOST_LIST = *` under `[webhook]` only; no
  `[security]` equivalent existed, so gitea used the deprecated fallback on every run.
- Fix: added `ALLOWED_HOST_LIST = *` to `[security]` and removed it from `[webhook]`.
- `app.ini` is a staged config file (`rootfs/tmp/etc/gitea/app.ini` → `/config/gitea/app.ini`), not a
  `gen-dockerfile`-generated file, so this is a normal in-repo edit, not a template/generation issue.
- Verified live on a rebuilt image: `gitea admin user create` no longer emits the deprecation warning,
  and admin login/API access still works normally after the move.
- Re-ran the full functional + restart-stability regression suite against this rebuilt image on fresh
  volumes: admin user creation, non-admin user creation, repo creation, fork (`forker/testrepo`), and
  GitHub mirror creation + manual `mirror-sync` trigger (`mirror_last_sync_at` moved off epoch) all
  passed. A 3x paced restart loop (90s settle each) and a 4x rapid back-to-back restart burst (3s
  apart) both left the container `running`/`ExitCode=0` throughout, with dockerd, `gitea web`, and all
  5 `act_runner` daemons (+ cache-server) alive afterward, and all 5 runner UUIDs byte-for-byte
  identical before and after (`/config/act_runner/reg/` still exactly 5 directories, no duplicates).

## App-breaking bug fixed — act_runner CI jobs cannot start: nested overlayfs mount failure (05-dockerd.sh)

- Every Gitea Actions job failed within ~13s with, both via act_runner and via a plain manual
  `docker run` inside the container: `failed to mount ... fstype: overlay ... err: invalid argument`.
  Reproduced with `docker exec gitea-test docker run --rm <any image> ...` — 100% failure rate, not
  specific to any one image or to act_runner's job-container logic.
- Root cause: the inner (DinD) dockerd defaulted to the `overlayfs` storage driver, same as the outer
  host/container's own root filesystem. Nesting an `overlay2`-driver dockerd inside a container whose
  own root is itself an overlay filesystem is a well-known Docker-in-Docker failure mode — the kernel
  rejects the resulting overlay-on-overlay mount with `invalid argument` on this kernel/host
  combination, even with `index=off` already set.
- Impact: **the entire act_runner CI subsystem was non-functional** — runners registered fine and
  showed as online, but every single job would fail immediately at the "Starting job container" step,
  regardless of workflow, label, or target image. This would not have been caught by
  container-startup/registration testing alone; it required actually running a real workflow to
  surface.
- Fix: added `"storage-driver": "fuse-overlayfs"` to both branches of the `/config/docker/daemon.json`
  generation in `__run_pre_execute_checks_local` (with-registry and without-registry cases).
  `fuse-overlayfs` is already bundled in the image (`/usr/bin/fuse-overlayfs`, `/dev/fuse` present) and
  avoids the kernel-level overlay-on-overlay conflict by mounting entirely in userspace via FUSE. The
  existing `--privileged`/`SYS_ADMIN` requirement (already documented in README.md as required for
  Docker-in-Docker) covers fuse-overlayfs's own requirements — no new run-flag requirement introduced.
- Verified live: manually patched `/config/docker/daemon.json` on the running container, restarted the
  inner dockerd, and confirmed `docker info` reports `Storage Driver: fuse-overlayfs` and `docker run`
  (both `casjaysdev/alpine:latest` and `ubuntu:latest`) now creates and starts containers successfully
  with no mount error, where it previously failed 100% of the time.
- **Follow-up root cause found**: the initial `05-dockerd.sh` heredoc fix alone did not take effect on
  a fresh container/fresh volumes. Traced to `__run_precopy`'s baked-`/etc`-seeding step: on first run
  it copies the whole baked `/etc/docker` directory (staged from `rootfs/tmp/etc/docker/daemon.json` via
  `03-files.sh`) into `/config/docker/` BEFORE `__run_pre_execute_checks_local`'s
  `[ ! -f "/config/docker/daemon.json" ]` guard ever runs — so the guard always saw the file already
  present and the heredoc (containing the fix) never executed. Fixed by adding
  `"storage-driver": "fuse-overlayfs"` to the actual baked source file,
  `rootfs/tmp/etc/docker/daemon.json`, in addition to keeping the `05-dockerd.sh` heredoc fix as
  defense-in-depth for any case where the baked `/etc/docker` dir is absent.
- Rebuilt the image and recreated the container on completely fresh volumes: confirmed
  `/config/docker/daemon.json` now contains `"storage-driver": "fuse-overlayfs"` and
  `docker info` reports `Storage Driver: fuse-overlayfs` via the normal init path (not a manual patch).
  Confirmed `docker exec gitea-test docker run --rm ubuntu:latest echo ...` succeeds with no mount
  error. Pushed a real `runs-on: alpine` Gitea Actions workflow via the contents API and confirmed the
  job reached `"status":"success"` in ~3 seconds via `GET .../actions/tasks` — full end-to-end
  confirmation, not just container-creation succeeding. **This bug is now fully resolved and verified.**
- Re-ran the full restart-stability + functional regression suite on this fix, on the same fresh
  container: 3x paced restarts (90s settle each) + 4x rapid-burst restarts (3s apart) — container
  stayed `running`/`ExitCode:0`/`healthy` throughout, all 5 runner UUIDs identical before/after (no
  duplicate registrations), and `Storage Driver: fuse-overlayfs` + prior admin user/repo state all
  survived the restarts intact. Also verified admin user creation, repo creation, fork (into a second
  `forker` user account), and mirror+sync (`mirror_updated` timestamp advanced from mirror-registration
  time to a fresh sync time) all still work with no regressions from this fix.

## AI.md compliance fixed — Dockerfile stale image.url and wrong HOSTNAME prefix

Found while reading the full repo tree; not previously logged.

- `Dockerfile` final stage: `LABEL org.opencontainers.image.url` used the stale
  `https://docker.io/casjaysdevdocker/forgejo` registry-pull form. AI.md PART 0 rule 5
  requires the browsable Docker Hub page URL. Fixed to
  `https://hub.docker.com/r/casjaysdevdocker/forgejo`.
- `Dockerfile` final stage: `ENV HOSTNAME="casjaysdev-${IMAGE_NAME}"` used the wrong org
  prefix. AI.md PART 2's HOSTNAME convention requires `casjaysdevdocker-${IMAGE_NAME}`
  (matching the build-stage `ENV HOSTNAME="casjaysdevdocker-forgejo"`, which was already
  correct). Fixed to `casjaysdevdocker-${IMAGE_NAME}`.

## Non-issue — confirmed intentional (`.gitea/workflows/docker.yaml`)

- Uses a stale/unpinned action pattern (`@v2`-`@v4`, DockerHub-only, `catthehacker/ubuntu:act-latest`).
  AI.md PART 7 explicitly documents this as the legacy hand-crafted workflow: "Never overwrite it,
  and never use it as a template for new work — it uses tag-pinned actions and retired secret
  names. All new/updated workflows come from `gen-dockerfile actions`." No `build.yml` exists yet in
  this repo; generating one is a separate task (running `gen-dockerfile actions`), not a fix to this
  file.
