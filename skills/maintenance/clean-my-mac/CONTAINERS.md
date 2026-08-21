# Container VM disk

The disk image behind colima or podman is usually the largest single file on a dev Mac. It grows to hold every image, layer, and volume ever written and **stays that size after you delete them inside the VM** — the guest frees the blocks, the host file keeps them allocated.

That is why every cleanup here ends in a **trim**.

## Locate and size the image

```bash
du -sh ~/.colima ~/.local/share/containers ~/.docker ~/.orbstack 2>/dev/null | sort -rh
```

Docker Desktop and OrbStack keep their images elsewhere and trim on their own terms — measure them the same way, and read their own docs before pruning.

colima keeps docker data on a lima *additional disk*, separate from the instance directory:

```bash
LIMA_HOME=~/.colima/_lima limactl disk ls
du -sh ~/.colima/_lima/_disks/*/datadisk
```

That disk is a named object owned by lima, so `colima delete` alone can leave it behind — a recreate that frees nothing while destroying every image. Pair the two:

```bash
colima delete
LIMA_HOME=~/.colima/_lima limactl disk delete <name>   # harmless if already gone
```

## Probe trim support before pruning

Whether the host file can shrink at all comes down to whether the guest's virtual disk advertises discard. One command answers it, and it is free to run first — before any pruning, when almost nothing is free inside the guest:

```bash
colima ssh -- sudo fstrim -av        # podman: podman machine ssh sudo fstrim -av
```

- Reports trimmed bytes → the mechanism works. Prune, then trim, then measure.
- `the discard operation is not supported` → no mechanism exists. Pruning will free space *inside* the VM but never on the host; the only way to shrink the file is recreating the VM. Say that plainly instead of proposing a prune that cannot move the host number.

## Prune in risk order

```bash
docker system df          # ACTIVE vs RECLAIMABLE per type
```

Confirm each of these with the user before running it — they are destructive infra, and the size at stake differs wildly per line:

| Target | Command | Risk |
|---|---|---|
| Build cache | `docker builder prune -af` | none when ACTIVE is 0 — rebuild once. Its size estimate is accurate. |
| Stopped containers | `docker container prune` | frees little itself, but unpins images and volumes so later prunes reach more |
| Unused images | `docker image prune -af` | re-pull. Yields **far less than RECLAIMABLE claims** — that figure sums layers shared with images you keep |
| Volumes | `docker volume prune` | **data loss.** Volumes attached to stopped containers hold databases. Hand the user `docker volume ls -f dangling=true` and `docker system df -v` and let them decide on their own schedule |

Then push the freed blocks back to the host and measure:

```bash
colima ssh -- sudo fstrim -av
du -sh ~/.colima/_lima/_disks/*/datadisk    # this number moving is the only proof
```

A cap keeps the build cache from regrowing to the same size. Check the flag name on the installed Docker (`docker builder prune --help`) — recent versions carry `--max-used-space`:

```bash
docker builder prune -f --max-used-space 10GB
```

## Right-size the VM, on measurements

`disk:` is a sparse ceiling — the provisioned number costs nothing, and shrinking it needs a recreate. Leave it.

`memory:` is also a ceiling rather than a reservation on `vmType: vz`, but the guest page cache grows toward it, so lowering it caps how much host RAM the VM can take. Decide from the live workload, not a rule of thumb:

```bash
colima ssh -- free -h
colima ssh -- cat /proc/pressure/memory      # avg10/avg60/avg300 at 0.00 means real headroom
docker stats --no-stream --format '{{.MemUsage}}\t{{.Name}}' | sort -rh | head
```

Compare `used` against the ceiling and keep 1.5–2 GiB of headroom for builds. When one compose stack dominates the total, stopping it when idle beats shrinking the ceiling — and it is reversible. Applying a new ceiling needs a restart (`colima stop && colima start --memory <N>`), which is itself a confirm-first command.

`cpu:` on vz is a soft share, not a reservation — leave it alone.

`rosetta` only pays when x86 images actually run. Count first, and skip the change when the answer is arm64:

```bash
docker image ls --format '{{.ID}}' | xargs docker image inspect --format '{{.Architecture}}' | sort | uniq -c
```

`mountType: virtiofs` is already the fastest option on vz.

## Retiring a runtime you stopped using

Machines accumulate runtimes. A `podman machine list` or `colima list` showing `LAST UP` months ago is pure reclaim — and each runtime is fully independent, with its own image store and socket, so removing one leaves the others working. Confirm which one `docker` actually talks to before touching anything:

```bash
docker context ls          # or read the socket path from any docker connection error
podman machine list        # NAME / LAST UP / DISK SIZE
```

Remove the machine first (that is where the gigabytes are), then the tooling. A CLI under `/opt/<name>` came from a pkg installer, so it needs sudo and has a `/etc/paths.d` entry to clear; anything from brew comes off with `brew uninstall`. Order matters when a helper daemon's binary lives inside the directory being deleted — uninstall the helper first.
