#!/usr/bin/env bash
# Smoke test: build a signed, initramfs-less UKI, then repeat with an
# absolute OUTPUT outside UKI_DIR. Finally check the mount guard fails closed.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Pick a readable kernel and its package name.
NAME=""
KERNEL=""
MODDIR="/usr/lib/modules/$(uname -r)"
if [[ -f $MODDIR/vmlinuz ]]; then
    KERNEL=$MODDIR/vmlinuz
    if [[ -f $MODDIR/pkgbase ]]; then
        NAME=$(<"$MODDIR/pkgbase")
    else
        NAME=$(uname -r)
    fi
else
    for f in /boot/vmlinuz-*; do
        [[ -f $f ]] || continue
        KERNEL=$f
        NAME=${f##*/vmlinuz-}
        break
    done
fi

[[ -n $KERNEL && -f $KERNEL ]] || {
    echo "smoke: no readable kernel image found" >&2
    exit 1
}

command -v openssl >/dev/null || { echo "smoke: openssl required" >&2; exit 1; }
command -v ukify >/dev/null || { echo "smoke: ukify required" >&2; exit 1; }
command -v sbverify >/dev/null || { echo "smoke: sbverify required" >&2; exit 1; }

openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$TMP/test.key" -out "$TMP/test.crt" -days 1 \
    -subj "/CN=ukibuild smoke/" >/dev/null 2>&1

common=$(cat <<EOF
MOUNT_GUARDS=("/")
SIGN_BACKEND="sbsign"
KEY="$TMP/test.key"
CERT="$TMP/test.crt"
MICROCODE_AUTO=0
BACKUP=0
INITRD["$NAME"]="none"
EOF
)

# 1. Relative output under UKI_DIR.
cat >"$TMP/ukibuild.conf" <<EOF
UKI_DIR="$TMP/esp/EFI/Linux"
$common
CMDLINE["$NAME"]="root=PARTLABEL=ROOT rw"
OUTPUT["$NAME"]="smoke.efi"
EOF

"$ROOT/ukibuild" -c "$TMP/ukibuild.conf" build "$NAME" --quiet
OUT="$TMP/esp/EFI/Linux/smoke.efi"
[[ -f $OUT ]] || { echo "smoke: output missing" >&2; exit 1; }
sbverify --cert "$TMP/test.crt" "$OUT" >/dev/null
"$ROOT/ukibuild" -c "$TMP/ukibuild.conf" verify "$NAME" --quiet

SECTIONS=$(ukify inspect "$OUT" 2>/dev/null | grep -E '^\.[a-z]' || true)
if grep -q '^\.initrd' <<<"$SECTIONS"; then
    echo "smoke: unexpected .initrd section" >&2
    exit 1
fi

# 2. Absolute output outside UKI_DIR.
cat >"$TMP/ukibuild-abs.conf" <<EOF
UKI_DIR="$TMP/esp/EFI/Linux"
$common
CMDLINE["$NAME"]="root=PARTLABEL=ROOT rw"
OUTPUT["$NAME"]="$TMP/outside/absolute.efi"
EOF

"$ROOT/ukibuild" -c "$TMP/ukibuild-abs.conf" build "$NAME" --quiet
ABS="$TMP/outside/absolute.efi"
[[ -f $ABS ]] || { echo "smoke: absolute output missing" >&2; exit 1; }
sbverify --cert "$TMP/test.crt" "$ABS" >/dev/null
"$ROOT/ukibuild" -c "$TMP/ukibuild-abs.conf" verify "$NAME" --quiet

# 3. CMDLINE from a file. CMDLINE_DEFAULT uses the same parser.
printf '# comment line\nroot=PARTLABEL=ROOT rw rootfstype=btrfs\n' >"$TMP/cmdline"
cat >"$TMP/ukibuild-file.conf" <<EOF
UKI_DIR="$TMP/esp/EFI/Linux"
$common
CMDLINE["$NAME"]="@$TMP/cmdline"
OUTPUT["$NAME"]="file-cmdline.efi"
EOF

"$ROOT/ukibuild" -c "$TMP/ukibuild-file.conf" build "$NAME" --quiet
FILE_OUT="$TMP/esp/EFI/Linux/file-cmdline.efi"
[[ -f $FILE_OUT ]] || { echo "smoke: file cmdline output missing" >&2; exit 1; }
sbverify --cert "$TMP/test.crt" "$FILE_OUT" >/dev/null
"$ROOT/ukibuild" -c "$TMP/ukibuild-file.conf" verify "$NAME" --quiet
if ! ukify inspect "$FILE_OUT" 2>/dev/null | grep -q 'rootfstype=btrfs'; then
    echo "smoke: cmdline file was not embedded" >&2
    exit 1
fi

# 4. list must not require ukify.
UKIFY=/nonexistent "$ROOT/ukibuild" -c "$TMP/ukibuild.conf" list --quiet >/dev/null

# 5. A relative UKI_DIR must fail.
cat >"$TMP/ukibuild-bad-dir.conf" <<EOF
UKI_DIR="relative"
SIGN_BACKEND="none"
CMDLINE["$NAME"]="root=PARTLABEL=ROOT rw"
INITRD["$NAME"]="none"
EOF

if "$ROOT/ukibuild" -c "$TMP/ukibuild-bad-dir.conf" build "$NAME" --quiet \
        >/dev/null 2>&1; then
    echo "smoke: relative UKI_DIR did not fail" >&2
    exit 1
fi

# 6. A guarded root that is not a mountpoint must fail.
cat >"$TMP/ukibuild-guard.conf" <<EOF
UKI_DIR="$TMP/esp/EFI/Linux"
MOUNT_GUARDS=("$TMP/not-mounted")
SIGN_BACKEND="none"
MICROCODE_AUTO=0
CMDLINE["$NAME"]="root=PARTLABEL=ROOT rw"
INITRD["$NAME"]="none"
OUTPUT["$NAME"]="$TMP/not-mounted/guard.efi"
EOF

if "$ROOT/ukibuild" -c "$TMP/ukibuild-guard.conf" build "$NAME" --quiet \
        >/dev/null 2>&1; then
    echo "smoke: mount guard did not fail" >&2
    exit 1
fi

echo "smoke test OK"
