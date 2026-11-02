# ukibuild

English | [简体中文](README.md)

A minimal UKI (Unified Kernel Image) build and signing tool.

- Uses `ukify` to bundle the kernel, optional initrds, and cmdline into a `.efi`
- **No initramfs required**: if none is found, none is added; or use
  `INITRD[name]="none"` explicitly
- **Arbitrary initrds**: whitespace-separated list; microcode is prepended
  automatically
- **Automatic signing**: uses sbctl if it is set up, otherwise sbsign with
  `/etc/efi-keys`
- **Atomic replacement**: the output is only moved into place after a
  successful build, signature, and verification; the old UKI survives failures
- **Automatic triggers**: pacman hook + systemd path unit

> `ukibuild` only bundles and signs. It does **not** generate an initramfs.
> Run mkinitcpio or dracut first for kernels that need one.

---

## Installation

```bash
cd ukibuild
sudo make install
```

| Path | Purpose |
|---|---|
| `/usr/bin/ukibuild` | Main program |
| `/etc/ukibuild.conf` | Configuration (example installed only if missing) |
| `/usr/share/libalpm/hooks/95-ukibuild.hook` | pacman hook |
| `/usr/lib/systemd/system/ukibuild.{path,service}` | systemd triggers |
| `/usr/share/doc/ukibuild/` | Documentation |

Uninstall with `sudo make uninstall` (keeps `/etc/ukibuild.conf`).

---

## Quick start

The configuration only needs one line (or none at all; the default is
`/efi/EFI/Linux`):

```bash
# /etc/ukibuild.conf
UKI_DIR="/efi/EFI/Linux"
```

Everything else is automatic:

- Kernels: `/boot/vmlinuz-*` and `/usr/lib/modules/*/vmlinuz`
- cmdline: `CMDLINE[name]` > `/etc/kernel/<name>-cmdline` >
  `CMDLINE_DEFAULT` > `/etc/kernel/cmdline`
- initramfs: `/boot/initramfs-<name>.img` if it exists, otherwise none
- Microcode: `/boot/amd-ucode.img` / `intel-ucode.img` if present
- Signing: sbctl if set up, otherwise sbsign

```bash
ukibuild list                  # show discovered kernels
sudo ukibuild build --all      # build everything
ukibuild verify                # check signatures
```

Run `sudo ukibuild build --all` once after installation; the path unit only
watches for later changes.

### Example: two kernels

Assume `linux` and `linux-lts`, with cmdline files at
`/etc/kernel/linux-cmdline` and `/etc/kernel/linux-lts-cmdline`, and only
`linux` needs an initramfs:

```bash
CMDLINE["linux"]="@/etc/kernel/linux-cmdline"
CMDLINE["linux-lts"]="@/etc/kernel/linux-lts-cmdline"

# linux uses /boot/initramfs-linux.img; linux-lts does not need one
INITRD["linux-lts"]="none"
```

To place UKIs on the root filesystem under `/boot` (not on the ESP):

```bash
UKI_DIR="/boot"
MICROCODE_AUTO=0
BACKUP=0
```

The outputs are `/boot/linux.efi` and `/boot/linux-lts.efi`.

To name the outputs `arch-*`:

```bash
OUTPUT["linux"]="arch-linux.efi"
OUTPUT["linux-lts"]="arch-linux-lts.efi"
```

---

## Configuration

### Global

| Variable | Default | Description |
|---|---|---|
| `UKI_DIR` | `/efi/EFI/Linux` | Output root (must be absolute) |
| `SIGN_BACKEND` | `auto` | `auto` / `sbctl` / `sbsign` / `none` |
| `CMDLINE_DEFAULT` | empty | Global cmdline; string, `@file`, or file path |
| `MICROCODE_AUTO` | `1` | Prepend amd/intel microcode automatically |
| `BACKUP` | `1` | Keep `<output>.bak` before replacing |
| `MOUNT_GUARDS` | `("/efi" "/boot/efi")` | These absolute paths must be real mountpoints |
| `UKIFY_EXTRA` | empty | Extra arguments passed to ukify |
| `KEY_DIR` | `/etc/efi-keys` | Directory scanned for the sbsign fallback |
| `KEY` / `CERT` | empty | Explicit sbsign key/certificate |

### Per-kernel

| Variable | Description |
|---|---|
| `CMDLINE[name]` | Literal cmdline, `@/path/to/file`, or a file path |
| `INITRD[name]` | Whitespace-separated initrd list; `none` / `""` means none |
| `OUTPUT[name]` | Relative to `UKI_DIR`, or an absolute path |

### cmdline resolution order

1. `CMDLINE[name]`
2. `/etc/kernel/<name>-cmdline`
3. `CMDLINE_DEFAULT`
4. `/etc/kernel/cmdline`

`CMDLINE[name]` and `CMDLINE_DEFAULT` accept three forms:

```bash
CMDLINE_DEFAULT="root=PARTLABEL=ROOT rw"
CMDLINE_DEFAULT="@/etc/kernel/cmdline"
CMDLINE_DEFAULT="/etc/kernel/cmdline"
```

Full-line `#` comments in files are ignored, and multiple lines are collapsed
into one. `CMDLINE_DEFAULT` is a fallback: it has lower priority than
`/etc/kernel/<name>-cmdline`.

### initrd rules

| Configuration | Behavior |
|---|---|
| `INITRD[name]` unset | Use `/boot/initramfs-<name>.img` if it exists; otherwise none |
| `INITRD[name]="none"` or `""` | Explicitly no root initramfs |
| `INITRD[name]="/a.img /b.img"` | Add multiple initrds in order |
| `MICROCODE_AUTO=1` | Prepend microcode to the list |

To remove the `.initrd` section entirely:

```bash
MICROCODE_AUTO=0
INITRD["linux"]="none"
```

To put microcode in a `.ucode` section instead of `.initrd`:

```bash
MICROCODE_AUTO=0
UKIFY_EXTRA=("--microcode=/boot/amd-ucode.img")
```

---

## Where to place UKIs

The default is the ESP:

```bash
UKI_DIR="/efi/EFI/Linux"
```

You can also use XBOOTLDR or the root filesystem:

```bash
UKI_DIR="/boot/EFI/Linux"   # XBOOTLDR mounted at /boot
UKI_DIR="/data/uki"         # root filesystem or another partition
```

`OUTPUT[name]` also accepts absolute paths:

```bash
OUTPUT["linux"]="/data/uki/arch-linux.efi"
```

### Mount checks

Before writing, `ukibuild` runs `mountpoint -q` on each root in
`MOUNT_GUARDS`. The default is:

```bash
MOUNT_GUARDS=("/efi" "/boot/efi")
```

- Output under a guard, but the guard is not mounted → **error**.
- Output outside every guard → continue; explicit absolute `OUTPUT` paths do
  not warn.
- `MOUNT_GUARDS=()` → disable the check.
- When using XBOOTLDR, add `"/boot"`.

> When a UKI is not on the ESP, the firmware cannot load it directly:
> XBOOTLDR requires systemd-boot; btrfs/ext4 requires rEFInd/GRUB filesystem
> drivers, and both the bootloader and its drivers must be trusted by Secure
> Boot.

---

## Signing

### `auto` (default)

1. sbctl is set up → `sbctl sign`
2. Otherwise a db key/cert exists in `/etc/efi-keys` → `sbsign`
3. Neither → error (`SIGN_BACKEND="none"` builds an unsigned image)

### `sbctl`

```bash
SIGN_BACKEND="sbctl"
```

Uses keys under `/var/lib/sbctl`. The output is not added to sbctl's database,
because every build re-signs it.

### `sbsign`

```bash
SIGN_BACKEND="sbsign"
KEY="/etc/efi-keys/db.key"
CERT="/etc/efi-keys/db.crt"
```

> The signing key must match the certificate enrolled in the firmware db.
> Before switching keys, check `sudo sbverify --list /boot/vmlinuz-*` and
> `sudo sbctl status`.

---

## Automatic triggers

- **pacman hook**: runs on kernel, initcpio, DKMS, systemd stub, and microcode
  updates.
- **systemd path unit**: watches `/boot`, `/usr/lib/modules`, and
  `/usr/lib/systemd/boot/efi`, so manually installed kernels also trigger a
  rebuild.

```bash
systemctl status ukibuild.path
journalctl -u ukibuild.service -b
```

---

## Commands

```bash
ukibuild build [name...]   # build (default)
ukibuild build --all       # everything
ukibuild list              # kernels, signing backend, output paths
ukibuild verify            # verify existing UKI signatures
ukibuild build -n -v       # dry run and print commands
```

Options:

```
-c, --config FILE   Config file
-n, --dry-run       Print only
-v, --verbose       Print commands
-q, --quiet         Warnings and errors only
    --all           All kernels
    --hook          Hook mode (--all --quiet)
```

A non-zero exit code means failure; the old UKI is not overwritten.

---

## Security notes

- The config is sourced as root; keep it `root:root 0644`.
- Paths in `UKI_DIR` and `MOUNT_GUARDS` must be absolute.
- Booting without an initramfs requires the root filesystem, storage
  controller, and other drivers to be built into the kernel (`=y`).
- With `MICROCODE_AUTO=1`, even `INITRD="none"` leaves a microcode-only cpio in
  `.initrd`; this is not a root initramfs.
- `BACKUP=1` uses another full UKI's worth of space; set `0` if the ESP is
  tight.
- After changing the cmdline you must rebuild; boot-menu arguments are ignored
  when Secure Boot is active.
- Keep the old boot entry for the first switch, and remove it only after the
  new UKI boots successfully.

---

## Troubleshooting

```bash
ukibuild list
sudo ukibuild build --all --dry-run --verbose
ukify inspect /efi/EFI/Linux/linux.efi | grep -E '^\.[a-z]'
sbverify --list /efi/EFI/Linux/linux.efi
journalctl -u ukibuild.service -b
```

| Error | Action |
|---|---|
| `no signing backend available` | Set `SIGN_BACKEND="none"` for testing only, or provide sbctl / sbsign keys |
| `is not a mountpoint` | ESP/XBOOTLDR is not mounted; check `findmnt` and `/etc/fstab` |
| `initrd not found` | The `INITRD[name]` path does not exist; run `mkinitcpio -P` first |
| `kernel image not found` | The kernel is not at `/boot/vmlinuz-<name>` or `/usr/lib/modules/*/vmlinuz` |
| Boot failure | Boot the old entry and inspect `.initrd` and the kernel's built-in drivers |

---

## License

MIT
