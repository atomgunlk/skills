---
name: clean-my-mac
description: Reclaim macOS disk space by measuring where it went, then freeing it with tool-native commands. Trigger on /clean-my-mac, "disk เต็ม" / disk full, "no space left on device" from a build or docker step, or leftover data from uninstalled apps.
---

# Clean my mac

Free real gigabytes and prove it with a before/after number. Dev machines lose space to caches and VM disk images, not to the user's files — so **measure first, and reconcile the total** before deleting anything.

`du` and `df` output is the **ground truth** here. Every number you cite comes from them, never from a tool's own claim about what it freed or could free.

## Step 1 — Measure and reconcile

```bash
df -h /System/Volumes/Data                          # the number you must move
du -sh ~/* 2>/dev/null | sort -rh | head -20
du -sh ~/.[!.]* 2>/dev/null | sort -rh | head -20   # dotdirs — usually the biggest offenders
du -sh /Applications /Library/Developer /opt/homebrew 2>/dev/null | sort -rh
tmutil listlocalsnapshots /                         # space du can never see
```

Then drill into every directory over ~5G with `du -sh <dir>/* | sort -rh | head`. These scans take minutes on a full disk — give them a generous timeout, or run the `/` scan in the background. Keep any globbed path in its own command: zsh aborts the whole line on an unmatched glob, silently skipping the commands after it.

**Reconcile before you act**: the dirs you named must sum to roughly the `Used` figure from `df`. Two traps hide the biggest directories:

- `~/*` skips every dotdir. The single biggest item is routinely `~/.colima`, `~/.local/share/containers`, `~/.ollama`, or `~/.gemini` — invisible to the plain glob.
- `du -x -d 1 /` double-counts `/System` (firmlink mirror of the Data volume). Read `/Users`, `/Applications`, `/Library`, `/opt` from it and ignore the `/System` row.

A **residual** that survives both traps is space `du` cannot reach, so name it instead of scanning again. The reason it stays invisible: **`du` prints the refusal to stderr, counts the path as zero, and exits as though the scan succeeded** — so the habitual `2>/dev/null` hides the single biggest cause of a residual. Probe with stderr visible and read which refusal comes back. Start from this list and expect the protected set to shift with the macOS version:

```bash
cd ~/Library && for p in Mail Messages Safari Cookies Accounts Biome Suggestions Shortcuts \
    "Application Support/FileProvider" "Application Support/Knowledge" "Metadata/CoreSpotlight"; do
  printf "%-40s " "$p"; du -sh "$p" 2>&1 | tail -1 | sed 's|.*: ||'
done
```

Repeat for `~/.Trash` and the volume root: `.DocumentRevisions-V100` (the Versions store behind Auto Save), `.Spotlight-V100`, `.fseventsd`, `.TemporaryItems`.

- `Operation not permitted` is **TCC**, where **sudo changes nothing** — only Full Disk Access for the host terminal opens it, and that hands every later command in that terminal the same reach. It is therefore the user's call: when they decline, report the blocked paths as a list saying what each one holds, and treat the residual as located rather than missing.
- `Permission denied` is ordinary POSIX, so `sudo du -sh` should read it (inferred from the mode bits, untested). `.fseventsd` lands here.
- **APFS local snapshots** from the `tmutil` line above are thinned with `sudo tmutil thinlocalsnapshots / <bytes> 4`.
- **Purgeable space** also explains an `Avail` figure that climbs by less than the bytes you freed.

Cross-check the figure you are chasing with `diskutil info /System/Volumes/Data | grep "Volume Used Space"` — it reports decimal GB against `df`'s GiB, so convert before concluding the two disagree.

**Sparse files**: for any VM or disk image, `ls -lh` shows the *apparent* size (a 100G file using 20G still reads 100G). Only `du -sh` shows blocks actually allocated.

**Done when** every directory over 5G is named, and the residual between their sum and `df Used` is either closed or attributed to specific paths you named as unreadable.

## Step 2 — Reclaim with tool-native commands

Native clean commands beat `rm -rf`: they are auditable, they skip live files, and they get approved where `rm -rf` gets denied.

| Target | Command | Cost of losing it |
|---|---|---|
| Go build cache | `go clean -cache` | rebuild once |
| Go module cache | `go clean -modcache` | re-download |
| npm cache | `npm cache clean --force` | re-download |
| npx package cache | `rm -r ~/.npm/_npx` | re-download |
| pip | `pip3 cache purge` | re-download |
| Homebrew | `brew cleanup -s`, then `rm -r ~/Library/Caches/Homebrew/downloads` | re-download |
| golangci-lint | `golangci-lint cache clean` | re-lint once |
| Rust | `rm -r ~/.cargo/registry/cache ~/.cargo/registry/src` | re-download |
| gradle / maven | `rm -r ~/.gradle/caches ~/.m2/repository` | re-download |
| Xcode | `rm -r ~/Library/Developer/Xcode/DerivedData` | rebuild |
| gopls, goimports, typescript, copilot | `rm -r ~/Library/Caches/<name>` | rebuild index |

Verify each command with `du -sh` on its directory instead of trusting its own report — two in this table under-deliver:

- `go clean` frequently exits `directory not empty` on the first run. **Run it a second time**, then confirm.
- `brew cleanup -s` reports megabytes while leaving `~/Library/Caches/Homebrew/downloads` at gigabytes, which is why the table pairs it with an explicit `rm`.

**Version-manager stores** — `~/.nvm`, `~/.rustup`, `~/.sdkman`, `~/.asdf`, `~/.pyenv` — hold installed runtimes rather than cache, so they stay out of the table above: the reclaim is real but conditional on reading the **pins** first. Ask the repos what they require:

Point `find` at wherever the repos live — `<repos>` below:

```bash
find <repos> -name .nvmrc -not -path '*/node_modules/*' -exec cat {} \; | sort -u
find <repos> -maxdepth 4 \( -name rust-toolchain -o -name rust-toolchain.toml \) -not -path '*/target/*'
```

Other managers pin through `.tool-versions`, `.sdkmanrc`, or `.python-version`. Keep every pinned version plus each manager's `default` alias target, delete the rest, and watch for two traps:

- A **pinned** runtime deleted is not reclaimed. The manager re-downloads it the next time anyone builds in that repo, trading disk for bandwidth at zero net gain — one `rust-toolchain.toml` naming an old channel is enough to make a gigabyte-scale removal pointless.
- A pin can name a version that is not installed (`.nvmrc` reading `24.13.0` while only `v24.13.1` exists). Match exactly before concluding a version is unused, since a near-miss satisfies nothing.

Managers exposed as shell functions, `nvm` among them, cannot be invoked: calling one means sourcing its init script, which the security rules forbid. Delete the version directory inside the store instead — these managers read that directory listing, so the effect is identical as long as the `default` alias still points at something you kept.

Container VM disk images (colima, podman, Docker Desktop, OrbStack) are the largest single item on most dev Macs. [`CONTAINERS.md`](CONTAINERS.md) carries their reclaim procedure, plus the right-sizing of a VM's disk, memory, and CPU — read it before touching them.

**Running apps hold their cache open.** Deleting the cache of a live Brave, Chrome, VS Code, or Electron app removes the directory but frees no space until the process exits. Check first, and route these to the hand-off list with "quit the app first":

```bash
for a in "Brave Browser" "Google Chrome" "Code" "Claude"; do pgrep -x "$a" >/dev/null && echo "RUNNING: $a"; done
```

**Done when** every approved target is either verified freed with `du -sh`, or moved to the Step 4 list.

## Step 3 — Sweep orphaned app data

Dragging an app to the Trash removes its executable and nothing else. Its data stays, survives every cache clean, and accumulates for years — so sweep for **orphans** whenever apps have been uninstalled, and check anyway, because old removals leave identical residue.

```bash
ls -1 /Applications ~/Applications 2>/dev/null | sed 's/\.app$//' | sort -u
du -sh ~/Library/Application\ Support/* 2>/dev/null | sort -rh
ls -1 ~/Library/Caches ~/Library/Preferences 2>/dev/null | sort -u
```

Anything in the last two lists with no counterpart in the first is a candidate. Bundle ids hide the match (`com.figma.Desktop` belongs to `Figma.app`), so confirm the app is really gone with `ls -d /Applications/<Name>.app` before proposing removal.

Read all three lists, because size and location both mislead: an app can leave 64K in `Application Support` and a gigabyte in `Caches`, or nothing at all beyond a plist and a `~/.<app>` dotdir. `Caches` and `Preferences` name every app that ever ran, which is why they belong in the detection pass. Even then the authoritative list is the user's, so ask which apps they removed: TCC keeps you out of `~/.Trash`, where the evidence sits.

One app scatters data across eight locations — sweep them per app, by display name and by bundle id:

```bash
cd ~/Library && for p in <name> <bundleid>; do
  find Caches HTTPStorages WebKit Logs "Application Support" Containers "Group Containers" Preferences \
    -maxdepth 1 -iname "*$p*" -print0 2>/dev/null | xargs -0 du -sh 2>/dev/null
done
```

Keep the `-print0 | xargs -0`: paths such as `Application Support/Figma` contain spaces, and a bare `$(find …)` splits them into broken arguments that `du` drops in silence, under-reporting a total by gigabytes. Then check `~/.<app>` dotdirs, and `~/Library/LaunchAgents` plus `/Library/LaunchAgents` and `/Library/LaunchDaemons` for updater helpers still launching for an app that no longer exists.

Confirm the list with the user before deleting — this is app data, not cache. Two things surprise reliably:

- An installer that ran with privileges leaves files **owned by root inside the user's own Library**, which refuse your `rm` with `Permission denied` and need a sudo hand-off.
- Some leftovers are worth keeping even with the app gone: a database client's saved connections and passwords, a license file, an editor's keymap. State what each app loses and let the user choose per app.

The Trash still holds the bundles themselves, and TCC keeps you out of `~/.Trash` — emptying it is the user's move, and usually the largest single item in this step.

**Done when** every app-data directory without an installed app is either removed, kept by the user's choice, or in the Step 4 hand-off.

## Step 4 — Hand off what you cannot run

Three classes of command belong to the user, not to you:

1. **`sudo` anything** — you cannot answer an interactive password prompt. A TCC refusal is not this class: sudo will not fix it, so hand over the path list and what each holds instead of a sudo command that fails the same way.
2. **A command the permission layer denied** — adjust once (a different path, or `rm -r` in place of `rm -rf`), and hand it over if it is denied again. Report the denial plainly rather than routing around it.
3. **Destructive infra** — `docker system/volume prune`, `docker volume rm`, `colima delete/stop`, `podman machine rm`, `kubectl delete`, `rm -rf` outside build dirs. Name the target, state what is lost, and wait for an OK **in the current turn**.

Hand off as a copy-paste block: one command per line, a comment carrying the size and what is lost, ordered so dependencies come first (uninstall a helper daemon before deleting the binary it lives in). Tell the user they can run it inline by prefixing `!` in the prompt.

```bash
# 1) launchd helper first — its binary lives in the dir deleted at step 2
sudo /opt/podman/bin/podman-mac-helper uninstall
# 2) CLI installed by pkg — 117M
sudo rm -rf /opt/podman
```

**Done when** every unrunnable target sits in the block with its size, its loss, and its order.

## Step 5 — Verify and report

```bash
df -h /System/Volumes/Data
```

Report the measured before/after `Used` and `Avail`. State which line items **you** verified and which the **user** ran off-transcript — a total that moved more than your own items account for means they ran some themselves, so attribute it that way instead of reconstructing a tidy ledger you did not observe.

**Done when** the before/after figures are reported and each freed item is attributed to whoever ran it.

## Expect it to regrow

Build caches and VM images refill at the speed of the work being done — a Go build cache reaching gigabytes within hours, a container disk image growing back between two runs of this skill. Treat the reclaim as recurring maintenance: re-run the tool-native commands and the trim rather than searching for something new, and reserve a fresh Step 1 scan for a gap the known targets cannot explain.

## Save what you learn

A machine's layout repeats every time it fills up, so the findings are worth a memory. Mark every inference as an inference: a future run trusts the line as tested unless it says otherwise.
