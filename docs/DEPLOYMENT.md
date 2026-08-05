# Deployment Runbook

How to deploy windex to a machine that is already in daily use — the family
tech-support case. You are on site once, the machine belongs to someone who
depends on it, and you want to leave with working remote access so there is no
second visit.

For a **fresh** machine, run `00-setup-master.bat` from the USB bundle instead;
this guide covers the harder case of an in-use machine with existing profiles,
existing software, and an existing way you reach it.

**The rule that governs the whole sequence:** whatever remote-access tool you
use today is your rescue channel. Retire it **last**, only after the
replacement is proven working from your own machine. Every phase below is
ordered around that constraint.

---

## Before you go

- [ ] Repo cloned and current
- [ ] A **Tailscale auth key**, minted **pre-approved** and **non-ephemeral**
      — see [SECURITY.md](SECURITY.md) for why those two settings matter. An
      ephemeral key deletes the node when the machine goes offline, which
      destroys your remote access the first time the lid closes.
- [ ] A VNC viewer on your machine ([TigerVNC](https://tigervnc.org) recommended,
      matching the server this installs)
- [ ] A password manager open, ready to receive the generated VNC password
- [ ] If you run a commercial VPN, know how you will reach the tailnet from it —
      many block Tailscale's CGNAT range (`100.64.0.0/10`) at their kill switch

---

## Phase 0 — Discovery snapshot

Take a read-only inventory **before touching anything**:

```powershell
# elevated PowerShell
Invoke-WebRequest https://github.com/jstoobz/windex/archive/refs/heads/main.zip -OutFile $env:TEMP\windex.zip
Expand-Archive $env:TEMP\windex.zip C:\provision -Force
C:\provision\windex-main\scripts\discover-machine.ps1 -OutFile C:\provision\before.txt
```

`discover-machine.ps1` makes no changes and never prints secrets. Read its
output before proceeding — in particular:

| Field | Why it matters |
|---|---|
| `Reboot pending` | Reboot **first**. A forced reboot mid-session is how half-applied state and duplicate profiles happen. |
| `AutoAdminLogon` / `DefaultPassword` | Should be `0` / absent. Leftover auto-logon is the root cause of duplicate lock-screen tiles. |
| `USER PROFILES` | An `ORPHANED` entry (profile with no matching account) explains duplicate tiles and should be cleaned. |
| `WINDEX MARKERS` | What prior windex runs recorded. Absent means nothing has run here. |
| `OpenSSH Capability` vs `sshd service` | `NotPresent` plus a running service means sshd came from the Win32-OpenSSH build rather than the Windows feature. |
| `Still provisioned` | Appx packages that any newly created profile will inherit. |
| VNC/SSH firewall rules | A `VNC-Block-All` rule from an old run blocks tailnet VNC and must be removed (Phase 5 does this). |

**Keep `before.txt`.** Phase 8 diffs against it, and that diff is your record of
everything the visit changed.

---

## Phase 1 — Insurance

1. Connect however you normally do (existing remote tool, or sit down at it).
2. Confirm the owner's backup is reasonably current before removing anything.
3. If `sshd` is broken — Windows feature updates reset the capability, service,
   and firewall profile — repair it now using the self-heal block in
   [TROUBLESHOOTING.md](TROUBLESHOOTING.md#openssh-issues). Working SSH lets you
   drive the rest from your own terminal instead of a remote GUI.

---

## Phase 2 — Debloat and nag suppression (machine scope)

Dry-run first, always. Elevated **cmd**, not PowerShell — these are `.bat`:

```bat
cd C:\provision\windex-main\scripts
35-debloat-apps.bat --dry-run
37-suppress-nags.bat --dry-run
```

Review the output: the Appx removal list should match what you expect to lose,
and the trialware census should name the OEM/AV junk you intend to remove. The
OneDrive step prints a warning and skips if it finds files stored there —
**trust that guard**; investigate rather than forcing it.

Then run for real, one script at a time, checking between:

```bat
35-debloat-apps.bat --verbose
37-suppress-nags.bat --verbose
```

Both are idempotent and safe to re-run.

---

## Phase 3 — Existing user profiles

Nag suppression seeds the Default user hive, which only reaches profiles created
**after** it runs. Existing profiles need their own pass. Sign in as that user
and run, **non-elevated**:

```bat
C:\provision\windex-main\scripts\37-suppress-nags.bat --user-only
```

Then **unpin dead Start tiles manually** (about 30 seconds). Removing an app
does not remove its Start pin, and for existing profiles those pins live in an
opaque `start2.bin` with no scripted path. Right-click each → Unpin.

Newly created profiles avoid this entirely — they inherit a curated layout from
the seeded `LayoutModification.json`.

---

## Phase 4 — Leftovers and reboot checkpoint

Some vendors leave residue that resists scripted removal. AV suites in
particular ship dedicated removal tools (McAfee's MCPR, Norton's NRnR) — run
those interactively; automating them is a rabbit hole and they want a reboot.

Reboot here, then verify the machine still does its job: the owner's daily
applications open, the Start menu is quiet, nothing obvious is missing.

**Stop if anything looks wrong.** Everything past this point touches the remote
access path, and you want a known-good machine underneath it.

---

## Phase 5 — Install remote access

Run at the keyboard, or over an SSH session that arrives via the tailnet —
**not** over an SSH session on a different path. This script re-scopes sshd to
the tailnet and will cut such a session mid-run, taking the closing banner
(and the password it prints) with it.

```powershell
$env:TS_AUTHKEY = 'tskey-auth-...'
C:\provision\windex-main\scripts\bootstrap-remote.ps1
```

This installs Tailscale and joins the tailnet, installs the TigerVNC server
from this repo's pinned release asset, generates and sets a VNC password,
scopes both VNC and SSH to `100.64.0.0/10`, and removes any legacy catch-all
VNC block rule (which would otherwise out-prioritize the allow rule and make
VNC unreachable — see [SECURITY.md](SECURITY.md)).

**Save the password immediately.** It is printed in the closing banner and
written to `C:\provision\output\credentials.txt`. If the run ended before the
banner, recover it from the registry — see
[TROUBLESHOOTING.md](TROUBLESHOOTING.md) → "Lost the VNC password". Note that
RFB truncates passwords to 8 significant characters.

To set your own password instead of a generated one:

```powershell
$env:VNC_PASSWORD = 'your-choice'
```

---

## Phase 6 — Prove it from your machine (the gate)

Do this from your own machine, not theirs. All three must succeed:

```bash
tailscale status --json    # their node present, "Online": true
tailscale ping <their-100.x-address>
open -a "TigerVNC Viewer" --args <their-100.x-address>:5900
```

You want an actual desktop on screen with the password accepted — not just a
ping. If the connection hangs while a commercial VPN is active on your side,
quit the VPN and retry before concluding anything is wrong with the target.

Confirm the firewall on their side shows exactly one rule on the VNC port:

```powershell
Get-NetFirewallPortFilter | Where-Object LocalPort -eq 5900 |
    Get-NetFirewallRule | Select-Object Name,Action
```

`VNC-Tailscale-Allow` / `Allow`, and nothing else. Any `Block` rule on that port
will defeat tailnet access regardless of rule order.

---

## Phase 7 — Retire the old remote-access tool

Only after Phase 6 fully passed:

1. Uninstall the previous tool (AnyDesk, TeamViewer, whatever got you here).
2. Confirm it is gone in a fresh discovery run.
3. **Reconnect once over the new channel** to prove it still works with the old
   one removed.

---

## Phase 8 — Closing snapshot

```powershell
C:\provision\windex-main\scripts\discover-machine.ps1 -OutFile C:\provision\after.txt
```

Diff `before.txt` against `after.txt`. Expect: debloat targets gone, Tailscale
present and approved, VNC server running with exactly one firewall rule, the old
remote tool absent, auto-logon still disarmed, no orphaned profiles.

Then finish up:

- [ ] VNC password stored in your password manager
- [ ] **Delete `C:\provision\output\credentials.txt`** — a deliberate step, not
      a scheduled one; a Windows update can outlive or disarm a scheduled task
- [ ] Copy both snapshots off the machine
- [ ] Optionally remove `C:\provision\windex-main`

---

## Abort criteria

Stop, keep the existing remote-access tool, and finish another day if:

- Discovery reports a pending reboot that will not clear
- A debloat step fails in a way that leaves software half-removed
- A daily-driver application breaks
- Phase 6 does not produce a live desktop over the tailnet
- The Tailscale node will not come back approved and online

None of these are emergencies — the machine still works and you can resume
later. The only unrecoverable mistake is retiring your rescue channel early.

---

## Rollback

`99-rollback.bat` reverses installation in inverse order, driven by the registry
markers each step wrote. It **overwrites and deletes** `output\credentials.txt`
before removing anything — save credentials elsewhere first.

Rollback does not restore removed Appx packages or uninstalled trialware. Those
are recoverable from the Microsoft Store and vendor sites respectively, but they
do not come back automatically.

---

## Related

- [SECURITY.md](SECURITY.md) — threat model, auth key settings, firewall posture
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) — symptom → cause → fix, including
  password recovery and post-feature-update sshd repair
- [ARCHITECTURE.md](ARCHITECTURE.md) — how the step scripts fit together
