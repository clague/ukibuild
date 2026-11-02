# ukibuild

[English](README.en.md) | 简体中文

一个极简的 UKI（Unified Kernel Image）构建与签名工具。

- 用 `ukify` 把 kernel、可选的 initrd、cmdline 打包成 `.efi`
- **支持无 initramfs**：找不到 initramfs 就不加；也可以显式 `INITRD[name]="none"`
- **支持任意 initrd**：空格分隔多个文件，微码自动前置
- **自动签名**：sbctl 已 setup 就用 sbctl，否则用 sbsign + `/etc/efi-keys`
- **原子替换**：构建/签名/验证成功后才 `mv`，失败保留旧 UKI
- **自动触发**：pacman hook + systemd path unit

> `ukibuild` 只负责打包和签名，**不生成 initramfs**。需要 initramfs 的内核先用 mkinitcpio / dracut 生成。

---

## 安装

```bash
cd ukibuild
sudo make install
```

| 路径 | 说明 |
|---|---|
| `/usr/bin/ukibuild` | 主程序 |
| `/etc/ukibuild.conf` | 配置（不存在时才安装示例） |
| `/usr/share/libalpm/hooks/95-ukibuild.hook` | pacman hook |
| `/usr/lib/systemd/system/ukibuild.{path,service}` | systemd 触发 |
| `/usr/share/doc/ukibuild/` | 文档 |

卸载：`sudo make uninstall`（保留 `/etc/ukibuild.conf`）。

---

## 快速开始

配置只需要一行（甚至可以不写，默认就是 `/efi/EFI/Linux`）：

```bash
# /etc/ukibuild.conf
UKI_DIR="/efi/EFI/Linux"
```

其余全自动：

- 内核：`/boot/vmlinuz-*` 和 `/usr/lib/modules/*/vmlinuz`
- cmdline：`CMDLINE[name]` > `/etc/kernel/<name>-cmdline` > `CMDLINE_DEFAULT` > `/etc/kernel/cmdline`
- initramfs：`/boot/initramfs-<name>.img` 存在就用，不存在就不加
- 微码：`/boot/amd-ucode.img` / `intel-ucode.img` 存在就前置
- 签名：sbctl 已 setup 就用 sbctl，否则 sbsign

```bash
ukibuild list                  # 看会发现哪些内核
sudo ukibuild build --all      # 构建所有
ukibuild verify                # 检查签名
```

首次安装后手动跑一次 `sudo ukibuild build --all`，因为 path unit 只监听后续变化。

### 示例：两个内核

假设你有 `linux` 和 `linux-lts`，cmdline 分别在
`/etc/kernel/linux-cmdline` 和 `/etc/kernel/linux-lts-cmdline`，并且只有
`linux` 需要 initramfs：

```bash
CMDLINE["linux"]="@/etc/kernel/linux-cmdline"
CMDLINE["linux-lts"]="@/etc/kernel/linux-lts-cmdline"

# linux 使用 /boot/initramfs-linux.img；linux-lts 不需要
INITRD["linux-lts"]="none"
```

如果想把 UKI 放 rootfs 的 `/boot`（不在 ESP）：

```bash
UKI_DIR="/boot"
MICROCODE_AUTO=0
BACKUP=0
```

输出就是 `/boot/linux.efi` 和 `/boot/linux-lts.efi`。`/boot` 不在默认
`MOUNT_GUARDS` 里，但因为 `UKI_DIR` 是显式设置的，不会触发警告。

如果想把输出命名成 `arch-*`：

```bash
OUTPUT["linux"]="arch-linux.efi"
OUTPUT["linux-lts"]="arch-linux-lts.efi"
```

### 从旧配置迁移

旧版本的 `ESP_DIR` + `OUT_DIR` 合并成一个 `UKI_DIR`：

```bash
# 旧
ESP_DIR="/efi"
OUT_DIR="EFI/Linux"

# 新
UKI_DIR="/efi/EFI/Linux"
```

`AUTO_DISCOVER`、`KERNELS`、`ENABLED`、`KERNEL`、`SPLASH`、`SIGN[name]`、`EXTRA_SIGN`、`CMDLINE_DEFAULT_FILE` 已移除，留在配置里会被忽略。`CMDLINE_DEFAULT` 仍然支持。

---

## 配置参考

### 全局

| 变量 | 默认值 | 说明 |
|---|---|---|
| `UKI_DIR` | `/efi/EFI/Linux` | 输出根目录（必须绝对路径） |
| `SIGN_BACKEND` | `auto` | `auto` / `sbctl` / `sbsign` / `none` |
| `CMDLINE_DEFAULT` | 空 | 全局 cmdline；字符串、`@file` 或文件路径 |
| `MICROCODE_AUTO` | `1` | 自动前置 amd/intel 微码 |
| `BACKUP` | `1` | 替换前保留 `<output>.bak` |
| `MOUNT_GUARDS` | `("/efi" "/boot/efi")` | 这些绝对路径必须是真实挂载点 |
| `UKIFY_EXTRA` | 空 | 追加给 ukify 的参数数组 |
| `KEY_DIR` | `/etc/efi-keys` | sbsign 回退时扫描的目录 |
| `KEY` / `CERT` | 空 | 显式指定 sbsign 密钥/证书 |

### 每内核

| 变量 | 说明 |
|---|---|
| `CMDLINE[name]` | cmdline 字面值、`@/path/to/file` 或文件路径 |
| `INITRD[name]` | 空格分隔的 initrd 列表；`none` / `""` 表示不加 |
| `OUTPUT[name]` | 相对 `UKI_DIR`，或绝对路径 |

### cmdline 解析顺序

1. `CMDLINE[name]`
2. `/etc/kernel/<name>-cmdline`
3. `CMDLINE_DEFAULT`
4. `/etc/kernel/cmdline`

`CMDLINE[name]` 和 `CMDLINE_DEFAULT` 都接受三种写法：

```bash
# 字面字符串
CMDLINE_DEFAULT="root=PARTLABEL=ROOT rw"

# @ 前缀
CMDLINE_DEFAULT="@/etc/kernel/cmdline"

# 已存在的文件路径
CMDLINE_DEFAULT="/etc/kernel/cmdline"
```

文件里的整行 `#` 注释会被忽略，多行会压成一行。

`CMDLINE_DEFAULT` 是回退值，优先级低于 `/etc/kernel/<name>-cmdline`。想让全局值覆盖所有内核，显式设置 `CMDLINE[name]`，或移除对应的 per-kernel 文件。

### initrd 规则

| 配置 | 行为 |
|---|---|
| `INITRD[name]` 未设置 | `/boot/initramfs-<name>.img` 存在就用，否则不加 |
| `INITRD[name]="none"` 或 `""` | 明确不加根 initramfs |
| `INITRD[name]="/a.img /b.img"` | 按顺序加入多个 initrd |
| `MICROCODE_AUTO=1` | 在列表最前面插入微码 |

想彻底不要 `.initrd` 段：

```bash
MICROCODE_AUTO=0
INITRD["linux"]="none"
```

想让微码走 `.ucode` 段而不是 `.initrd`：

```bash
MICROCODE_AUTO=0
UKIFY_EXTRA=("--microcode=/boot/amd-ucode.img")
```

---

## UKI 放在哪里

默认是 ESP：

```bash
UKI_DIR="/efi/EFI/Linux"
```

也可以放 XBOOTLDR 或根分区：

```bash
# XBOOTLDR 挂载在 /boot
UKI_DIR="/boot/EFI/Linux"

# 根分区 / 其他分区
UKI_DIR="/data/uki"
```

`OUTPUT[name]` 也支持绝对路径：

```bash
OUTPUT["linux"]="/data/uki/arch-linux.efi"
```

### 挂载检查

`MOUNT_GUARDS` 里的根目录，在写入前会用 `mountpoint -q` 确认是真挂载点。默认：

```bash
MOUNT_GUARDS=("/efi" "/boot/efi")
```

- 输出在某个 guard 下，但该 guard 没挂载 → **报错**，避免把 UKI 写到 rootfs 上的同名空目录。
- 输出不在任何 guard 下 → 继续。显式写了绝对 `OUTPUT` 时不警告（视为有意选择）；否则警告。
- `MOUNT_GUARDS=()` → 完全关闭检查。
- 用 XBOOTLDR 时把 `"/boot"` 加进去。

例如把 UKI 放在 rootfs 的 `/boot`：

```bash
OUTPUT["linux"]="/boot/linux.efi"
```

因为 `/boot` 不在默认 guard 里，而且是显式绝对路径，所以不会报错也不会警告。如果你希望 `/boot` 必须是挂载点，就加：

```bash
MOUNT_GUARDS=("/efi" "/boot/efi" "/boot")
```

> UKI 不在 ESP 时，固件不能直接加载它：XBOOTLDR 需要 systemd-boot；btrfs/ext4 需要 rEFInd/GRUB 的文件系统驱动，并且引导器和驱动都要被 Secure Boot 信任。

---

## 签名

### `auto`（默认）

1. sbctl 已 setup → `sbctl sign`
2. 否则 `/etc/efi-keys` 下有 db key/cert → `sbsign`
3. 都没有 → 报错（`SIGN_BACKEND="none"` 可构建未签名镜像）

### `sbctl`

```bash
SIGN_BACKEND="sbctl"
```

使用 `/var/lib/sbctl` 的密钥。签完不写入 sbctl 数据库，因为每次构建都会重新签。

### `sbsign`

```bash
SIGN_BACKEND="sbsign"
KEY="/etc/efi-keys/db.key"
CERT="/etc/efi-keys/db.crt"
```

> 签名密钥必须和固件 db 里登记的证书匹配。换密钥前先 `sudo sbverify --list /boot/vmlinuz-*` 和 `sudo sbctl status` 确认。

---

## 自动触发

### pacman hook

内核、initcpio、DKMS、systemd stub、ucode 更新时执行：

```bash
/usr/bin/ukibuild build --all --quiet
```

### systemd path unit

监听 `/boot`、`/usr/lib/modules`、`/usr/lib/systemd/boot/efi`，手动 `make install` 的内核也会触发。`flock` 防止并发，service 启动前 `sleep 2` 合并同一批写入。

```bash
systemctl status ukibuild.path
journalctl -u ukibuild.service -b
```

---

## 命令

```bash
ukibuild build [name...]   # 构建（默认）
ukibuild build --all       # 所有
ukibuild list              # 内核、签名后端、输出路径
ukibuild verify            # 验证已有 UKI 签名
ukibuild build -n -v       # 空跑并打印命令
```

选项：

```
-c, --config FILE   指定配置文件
-n, --dry-run       只打印
-v, --verbose       打印命令
-q, --quiet         只输出警告/错误
    --all           所有内核
    --hook          hook 模式（--all --quiet）
```

失败时退出码非 0，且不会覆盖旧 UKI。

---

## 工作流程

1. 解析 kernel / cmdline / initrd / output
2. 检查输出所在挂载点
3. `ukify build` 到临时文件
4. 用 sbctl 或 sbsign 签另一个临时文件
5. `sbverify` 验证
6. 可选保留 `.bak`
7. `fsync` 后 `mv` 原子替换

---

## 安全与注意事项

- 配置文件以 root 身份 source，权限保持 `root:root 0644`。root 下会拒绝 group/world-writable 的配置，非 root 只警告。
- `UKI_DIR` 和 `MOUNT_GUARDS` 里的路径必须是绝对路径。
- 无 initramfs 启动要求根文件系统、存储控制器等驱动**编进内核**（`=y`）。检查：
  ```bash
  /usr/src/linux/scripts/extract-ikconfig /boot/vmlinuz-linux \
    | grep -E 'CONFIG_(BLK_DEV_NVME|NVME_CORE|BTRFS_FS)='
  ```
- `MICROCODE_AUTO=1` 时，即使 `INITRD="none"`，`.initrd` 里也只有一个微码 cpio，不是根 initramfs。
- `BACKUP=1` 会多占一份 UKI 的空间；ESP 紧张时设 `0`。
- 改 cmdline 后必须重建；Secure Boot 下启动菜单传参无效。
- 首次切换保留旧启动项，测试新 UKI 能启动后再清理。

---

## 故障排查

```bash
ukibuild list
sudo ukibuild build --all --dry-run --verbose
ukify inspect /efi/EFI/Linux/linux.efi | grep -E '^\.[a-z]'
sbverify --list /efi/EFI/Linux/linux.efi
journalctl -u ukibuild.service -b
```

| 错误 | 处理 |
|---|---|
| `no signing backend available` | 配置 `SIGN_BACKEND="none"` 仅测试，或准备 sbctl / sbsign 密钥 |
| `is not a mountpoint` | ESP/XBOOTLDR 没挂载，检查 `findmnt` 和 `/etc/fstab` |
| `initrd not found` | `INITRD[name]` 路径不存在，先跑 `mkinitcpio -P` |
| `kernel image not found` | 内核不在 `/boot/vmlinuz-<name>` 或 `/usr/lib/modules/*/vmlinuz` |
| 启动失败 | 用旧启动项进入，检查 `.initrd` 内容和内核内置驱动 |

---

## AUR 发布

AUR 打包文件在 `packaging/aur/`：

```bash
packaging/aur/
├── PKGBUILD
├── ukibuild.install
└── README.md
```

`.github/workflows/aur.yml` 会在推送 `v*` tag（或手动触发）时：

1. 在 Arch 容器里构建并校验包
2. 自动填充 `pkgver`、`_owner`、`_repo`、`sha256sums`
3. 生成 `.SRCINFO`
4. 推送到 `ssh://aur@aur.archlinux.org/ukibuild.git`

首次使用需要：

- AUR 账户，并把 AUR SSH 公钥加到账户
- 在 GitHub 添加 `AUR_SSH_PRIVATE_KEY` secret

不需要手动在 AUR 网页创建包：新包 clone 下来是空仓库，第一次 push 会自动创建。

详细步骤见 `packaging/aur/README.md`。

> 这是稳定版包，按 tag 发布。如果你想每次 commit 都自动更新 AUR，应该另做一个 `ukibuild-git` 包。

## 开发与测试

```bash
make check    # bash -n + shellcheck（如果安装）
make test     # 临时密钥构建无 initramfs UKI，签名并验证
```

---

## 目录结构

```
ukibuild/
├── ukibuild                          # 主程序
├── ukibuild.conf.example             # 配置示例
├── hooks/95-ukibuild.hook            # pacman hook
├── units/ukibuild.service            # systemd oneshot
├── units/ukibuild.path               # systemd path watcher
├── tests/smoke.sh                    # 冒烟测试
├── packaging/aur/                    # AUR 打包
│   ├── PKGBUILD
│   ├── ukibuild.install
│   └── README.md
├── .github/workflows/aur.yml         # tag -> AUR 发布
├── Makefile
├── README.md                         # 中文
├── README.en.md                      # English
└── LICENSE
```
