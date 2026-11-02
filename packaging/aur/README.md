# AUR packaging

Files:

```
packaging/aur/
├── PKGBUILD
├── ukibuild.install
└── README.md
```

The GitHub Actions workflow is `.github/workflows/aur.yml`.

## What the workflow does

On a `v*` tag (or manual dispatch):

1. Runs in an Arch Linux container.
2. Fills `_owner` / `_repo` from the GitHub repository.
3. Sets `pkgver` from the tag (strips leading `v`, replaces `-` with `_`).
4. Runs `updpkgsums` to fill `sha256sums`.
5. Generates `.SRCINFO`.
6. Builds the package with `makepkg -s -f` to validate it.
7. Clones `ssh://aur@aur.archlinux.org/ukibuild.git` and pushes
   `PKGBUILD`, `.SRCINFO`, and `ukibuild.install` if they changed. For a new
   package the clone is empty and the **first push creates the package**.

It does **not** push on every commit. A stable AUR package should change when
the version changes, i.e. on a release tag. If you want every commit to be
available, publish a separate `ukibuild-git` package instead.

## First-time setup

### 1. AUR account and SSH key

You do **not** need to create the package in the AUR web interface. The first
successful push creates it.

- Create an AUR account.
- Add your SSH public key to the AUR account.

You can verify access before the first release:

```bash
git -c init.defaultBranch=master clone ssh://aur@aur.archlinux.org/ukibuild.git
# warning: You appear to have cloned an empty repository.
```

An empty clone is expected for a new package. Do not push from this test clone
unless you want to create the package manually; the workflow does it.

If the package name is already taken by another user, choose a different
`pkgname`, `install=` filename, and set the GitHub repository variable
`AUR_PACKAGE` (Settings → Variables → Actions). Otherwise it defaults to
`ukibuild`.

### 2. Add the AUR SSH key to GitHub

Generate a dedicated key without a passphrase:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/aur_ukibuild -C "aur ukibuild"
```

- Add `~/.ssh/aur_ukibuild.pub` to your AUR account.
- Add the **private** key as a GitHub Actions secret named
  `AUR_SSH_PRIVATE_KEY` (Settings → Secrets and variables → Actions → Secrets).

The workflow writes it to `~/.ssh/aur` with mode 0600 and pins
`aur.archlinux.org` in `known_hosts`.

### 3. Maintainer line

`PKGBUILD` uses:

```bash
# Maintainer: clague <clague [at] clague [dot] moe>
```

The address is intentionally obfuscated so address-harvesting crawlers cannot
scrape it directly. `makepkg` treats this line as a comment, so the brackets
are harmless. A human can reconstruct it by replacing `[at]` with `@` and
`[dot]` with a dot.

## Release process

1. Bump `VERSION` in the `ukibuild` script.
2. Commit and push to `main`.
3. Create and push a tag:

```bash
git tag v0.3.1
git push origin v0.3.1
```

4. The workflow updates the AUR repository automatically.

`pkgrel` is reset to `1` on every tag. For a packaging-only change without a
new upstream tag, run the workflow manually and bump the tag/version as
appropriate (or temporarily edit `pkgrel`).

The tag is also checked against `readonly VERSION="..."` in the `ukibuild`
script, so remember to bump both together. Arch's `pkgver` cannot contain `-`;
the workflow converts `-` to `_`, so prefer tags like `v0.3.1` or
`v0.3.1rc1`.

## Local test build

```bash
cd packaging/aur
sed -i 's/^_owner=.*/_owner="your-github-user"/' PKGBUILD
updpkgsums
makepkg -si
```

`updpkgsums` is provided by `pacman-contrib`. The committed `PKGBUILD` uses
`sha256sums=('SKIP')` because the workflow fills the real checksum on release.

## Notes

- `ukibuild.install` is an AUR metadata file; it is copied to the AUR repo by
  the workflow and referenced by `install=ukibuild.install` in `PKGBUILD`.
- Do not commit a generated `.SRCINFO` to this repository; the workflow
  regenerates it.
- The package installs `/etc/ukibuild.conf` as a backup file, so upgrades leave
  your configuration alone (and may create `.pacnew`).
- The systemd units are installed but not enabled. After installing, run:

```bash
sudo systemctl enable --now ukibuild.path
```
