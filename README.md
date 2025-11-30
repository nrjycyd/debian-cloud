# 🚀 Debian Cloud OVA Builder (Internal Tools)

这是一个用于自动化构建 Debian Cloud 镜像（OVA 格式）的工具集。它基于 **Debian 官方云镜像**（`genericcloud`，源自 [cloud.debian.org](https://cloud.debian.org/images/cloud/)），通过封装 Cloud-Init 配置，快速生成可直接导入 **VMware ESXi**、**VMware Workstation** 以及 **VirtualBox** 的虚拟机模板。

> [\!CAUTION]
> **⚠️ 安全警告：仅限内部测试环境使用**
>
>   * 本工具生成的镜像包含预设的**默认凭据**。
>   * **绝对不要**将生成的 OVA 文件直接部署到公网或生产环境，除非你已在构建时注入了安全的 SSH Key 并禁用了密码登录。
>   * 部署后必须**第一时间修改密码**。

-----

## ✨ 功能特性

  * **官方源构建**：基于稳健的官方源 `https://cloud.debian.org/images/cloud/` 构建，确保纯净安全。
  * **多版本支持**：支持 Debian 11 (Bullseye), 12 (Bookworm), 13 (Trixie), 以及 Sid。
  * **硬件定制**：构建时可自定义 vCPU、内存和磁盘大小（支持小规格，如 2GB+ 磁盘）。
  * **自动化集成**：支持 GitHub Actions 一键构建并发布 Release。
  * **Cloud-Init**：自动注入主机名、默认用户和 SSH 公钥。

-----

## 🛠️ 快速开始 (GitHub Actions)

这是最推荐的使用方式，无需本地环境。

1.  进入项目的 **Actions** 页面。
2.  选择 **"🚀 Build & Release Debian OVA"** 工作流。
3.  点击 **Run workflow** 按钮。
4.  根据需求填写参数：
      * `Debian Version`: 推荐 `bookworm` 或 `trixie`。
      * `Disk size`: 默认为 10GB，**最小设置为 2GB**。
      * `Password`: 设置初始密码（构建日志中可见，请注意安全）。
5.  构建完成后，在 **Releases** 页面下载生成的 `.ova` 文件。

-----

## 💻 本地构建 (CLI)

如果你需要在本地 Linux 环境下运行脚本：

### 前置依赖

```bash
sudo apt update
sudo apt install -y wget qemu-utils tar
```

### 构建命令示例

```bash
chmod +x ./debian-ova-creator.sh

# 构建一个 2核 1G内存 4G硬盘的 Debian 12 镜像
sudo ./debian-ova-creator.sh \
  -d "bookworm" \
  -c "2" \
  -m "1024" \
  -s "4" \
  -H "debian-test-node" \
  -u "admin" \
  -p "MySecretPass123"
```

-----

## 🔐 安全操作指南 (必读)

由于 OVA 镜像使用了预设密码，系统启动后存在极大安全风险。请务必执行以下操作：

### 1\. 首次登录

  * **控制台登录**：使用 VMware/ESXi 的 Web Console 或 VMRC。
  * **SSH 登录**：`ssh <username>@<ip-address>`
  * **默认凭据**：如果构建时未修改，默认为 `debian` / `123456`。

### 2\. 修改默认用户密码 (高优先级)

登录系统后，立即运行以下命令修改当前用户的密码：

```bash
sudo passwd debian
```

系统会提示：

1.  输入当前密码 (`Current password`)
2.  输入新密码 (`New password`)
3.  确认新密码 (`Retype new password`)

### 3\. 修改/锁定 Root 密码

默认情况下 Debian Cloud 镜像锁定了 Root 登录，但在使用 `sudo` 提权后，建议重置 Root 密码或确保其处于锁定状态。

**设置 Root 密码（如需）：**

```bash
sudo passwd root
```

### 4\. 强制定期修改 (可选 - 适用于测试团队)

如果你是管理员，希望强制使用者在第一次登录时必须修改密码，请在虚拟机启动后运行：

```bash
sudo chage -d 0 <username>
# 例如：sudo chage -d 0 debian
```

*效果：用户下次登录时，系统会强制要求其立即更改密码，否则无法进入 Shell。*

-----

## ⚙️ 初始系统配置

### 1. 替换软件源

> [!note]
>
> Debian 13 软件源变更为 `DEB822` 格式 `/etc/apt/sources.list.d/debian.sources` ，不再是传统格式 `/etc/apt/sources.list`

将 `/etc/apt/sources.list.d/debian.sources` 中默认源全部删除，将其替换为清华源

```
Types: deb
URIs: https://mirrors.tuna.tsinghua.edu.cn/debian
Suites: trixie trixie-updates trixie-backports
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

# 默认注释了源码镜像以提高 apt update 速度，如有需要可自行取消注释
# Types: deb-src
# URIs: https://mirrors.tuna.tsinghua.edu.cn/debian
# Suites: trixie trixie-updates trixie-backports
# Components: main contrib non-free non-free-firmware
# Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

# 以下安全更新软件源包含了官方源与镜像站配置，如有需要可自行修改注释切换
Types: deb
URIs: https://security.debian.org/debian-security
Suites: trixie-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

# Types: deb-src
# URIs: https://security.debian.org/debian-security
# Suites: trixie-security
# Components: main contrib non-free non-free-firmware
# Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
```
更新源

```
sudo apt update
```

### 2. 安装虚拟机工具集（非必须）

Debian Cloud 镜像安装时，如果未联网可能出现工具集安装失败，建议手动安装。

```bash
sudo apt install open-vm-tools
```

### 3. 修改时区 (Timezone)

默认时区为 UTC。如果你在中国大陆地区使用，建议修改为 `Asia/Shanghai` (CST)。

```bash
sudo dpkg-reconfigure tzdata
```

-----

## ❓ 常见问题

**Q: 导入 VMware 后无法获取 IP？**
A: 镜像使用 Cloud-Init 配置网络（DHCP）。请确保你的 VMware 网络适配器已连接，并且该网段内有可用的 DHCP 服务。

**Q: 构建日志里能看到我的密码吗？**
A: 是的。目前的构建脚本通过命令行传递密码，Github Actions 日志会明文记录。因此再次强调：**仅限内部测试使用，生产环境请使用 SSH Key 注入并禁用密码登录。**
