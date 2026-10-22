# Izolation: analysis, changes, plan

Goal: every account looks like a separate installation on the same machine.
Shared public IP is accepted and not addressed here.

## 1. Already isolated upstream

- Each window is a separate Chromium `--user-data-dir`: cookies, IndexedDB,
  localStorage, token cache (`config.json`), `ccd-ids.json`, `plan-usage-history.json`,
  `logs`, Crashpad, caches.
- `ant-did` is the install id: `randomUUID()` written into
  `app.getPath("userData")` (`app.asar`, functions `hHt`/`k5`). The file is protected
  against hardlink substitution (`lstat`, `nlink > 1` → re-read).
- Telemetry sends `install_id`/`device_id` as that UUID; measured on two local
  profiles: `<install-id-A>` vs `<install-id-B>` (different).
- The sibling import scans only `%LOCALAPPDATA%\*-Data`; profiles kept outside that
  directory are not touched.

## 2. What used to be shared and how it is fixed

| Channel | Before | After |
|---|---|---|
| `~\.claude` (projects, sessions, telemetry, skills) | shared by all windows and terminal Claude Code | `CLAUDE_CONFIG_DIR=<profile>\claude-config` |
| `~\.claude.json` (`machineID`, `userID`, `oauthAccount`) | one machine id per machine | own `.claude.json` per `claude-config` |
| Claude Code credentials (Credential Manager) | `Claude Code-credentials` without suffix | key includes the config-dir hash (`Claude Code-credentials-<hash>`) |
| `%TEMP%` / `%TMP%` | shared | `<profile>\temp` |
| `remoteToolsDeviceName` | hostname | `device-<10 hex>` at account creation |
| Essential telemetry (Sentry, Datadog RUM: CPU, RAM, manufacturer/model, screen) | enabled | optional: `ccm telemetry <name> off` → `--desktop-managed-config={"disableEssentialTelemetry":true}` |
| `claude://` links | always the main Claude window | not fixable (Windows has one handler) |
| `anthropic-client-*` headers (RAM class, OS, version) | identical | not fixable client-side |
| IP, hardware, OS hostname, payments, email | — | outside the client |

## 3. Code changes

`ClaudeAccounts.cs`, `Accounts.Open`:
- creates `<profile>\claude-config` and `<profile>\temp`;
- for the duration of the window start sets `CLAUDE_CONFIG_DIR`, `TEMP`, `TMP`,
  `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`, then restores the previous values;
- when `<profile>\no-telemetry` exists, appends
  `--desktop-managed-config={"disableEssentialTelemetry":true}`.

`ccm.ps1`:
- `Initialize-Isolation` — creates the directories and a random device name;
- `ccm add` calls it for a new account;
- `ccm isolate <name>` — adds isolation files to an existing account;
- `ccm doctor` — table of install id / machine id / device name / config and temp
  directories, plus duplicate detection;
- `ccm claude <name> [args]` — runs the Claude Code CLI with the account's config dir;
- `ccm telemetry <name> off|on` — toggles the essential-telemetry block.

## 4. Verification performed

- Window opens: `claude-desktop.exe --user-data-dir=...\accounts\<name>`.
- Child process environment (read from PEB):
  ```
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
  CLAUDE_CONFIG_DIR=<root>\accounts\<name>\claude-config
  TEMP=<root>\accounts\<name>\temp
  TMP=<root>\accounts\<name>\temp
  ```
- `ccm claude <name> config list` created the account's own `.claude.json`,
  `projects`, `sessions`, `backups`; `machineID` differs from the main app's,
  `userID` differs too; `~\.claude.json` was not modified.
- `ccm telemetry <name> off` → the window command line contains
  `--desktop-managed-config={"disableEssentialTelemetry":true}` and the window
  still starts.
- `ccm doctor` shows different ids for the main app and an account.

## 5. Possible next steps

1. `--proxy-server` per window if IP separation is ever needed.
2. Block essential telemetry by default for new accounts.
3. Real hardware isolation — Windows Sandbox / a VM per account.
4. `ccm doctor --fix` to regenerate device names and config directories.

## 6. Rollback

Restore `ClaudeAccounts.cs` and `ccm.ps1` from upstream, then `ccm build` and
`ccm install`. Account data lives in `accounts\<name>` and is removed by
`ccm remove <name>`.
