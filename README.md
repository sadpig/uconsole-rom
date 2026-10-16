# uConsole 全能 ROM 打包方案

基于 Ubuntu 的定制镜像：一张 SD 卡内置渗透测试、SDR 无线电、Meshtastic、复古游戏、编程、离线知识库、音乐制作、运维终端、本地 LLM 九大类应用。

## 前提假设

- **核心板：Raspberry Pi CM4 或 CM5**（最常见，Ubuntu 支持最好）。
  A-06 用户：思路相同，但基础镜像要换成 clockworkpi 论坛的 A-06 Ubuntu 帖，
  个别包名可能不同，脚本的 `a|b` 备选写法会自动兜底一部分。
- **SD 卡 ≥ 64GB**（推荐 128GB：全部应用 + 模型 + ZIM 文件很吃空间）。
- 一台能上网的电脑（下载镜像、最后备份用）。

## 分类清单总览

| 分类 | 清单文件 | 主要内容 |
|---|---|---|
| base | `10-base.list` | 中文字体、zram、4G/GPS/对时底座 |
| ops | `20-ops-net.list` | SSH/mosh/tmux、串口、iperf3、WireGuard、RDP |
| pentest | `30-pentest.list` | nmap、aircrack-ng、kismet、bettercap、hashcat |
| sdr | `40-sdr-radio.list` | gqrx、dump1090、rtl_433、direwolf、gpredict、SDR++ |
| mesh | `50-mesh-comms.list` | meshtasticd + CLI（需 AIO 板的 SX1262） |
| games | `60-games.list` | RetroArch + 核心、mednafen、DOSBox、Nethack |
| dev | `70-dev.list` | gcc/python/node/go/rust、neovim、docker |
| writing | `80-writing-knowledge.list` | kiwix 离线维基、focuswriter、wordgrinder |
| music | `90-music.list` | milkytracker、audacity、pipewire |
| llm | `95-llm.list` | ollama + 小模型 |

> 想精简：直接编辑对应 `.list` 文件注释掉行，或用 `--skip` 跳过整个分类。

## 路线 A：在设备上定制（推荐，最不容易踩坑）

```bash
# 1. 下载基础镜像（二选一）
#    - 社区 Ubuntu 镜像（推荐）：clockworkpi 论坛搜 "Ubuntu"，找 Rex 维护的帖，
#      自带 uConsole 全部驱动（屏幕/键盘/背光/电池）
#    - 官方 Ubuntu for Raspberry Pi：干净但要自己补 uConsole 内核补丁
#      （补丁在 github.com/clockworkpi/uConsole）

# 2. 刷到 SD 卡（Raspberry Pi Imager 或 balenaEtcher）

# 3. 插卡开机，联网，把本目录拷进去后：
cd uconsole-rom
chmod +x customize.sh
sudo ./customize.sh                     # 全家桶
# sudo ./customize.sh --skip "llm music"  # 按需裁剪
```

## 路线 B：在电脑上离线定制（可重复构建）

macOS 不能直接挂 ext4，需要一个 Linux VM（UTM / OrbStack / Multipass 都行）：

```bash
# VM 内：
unzip *ubuntu*.img.zip && mv *.img uconsole-aio.img

# 扩容镜像并挂载根分区（假设镜像内第二个分区是 rootfs）
qemu-img resize uconsole-aio.img +8G
sudo losetup -fP --show uconsole-aio.img      # 记下列环回设备，如 /dev/loop0
sudo mount /dev/loop0p2 /mnt
sudo mount /dev/loop0p1 /mnt/boot/firmware    # 第一分区是 boot

# chroot 进去跑同一个脚本（需要 qemu-user）
sudo apt install qemu-user-static
sudo cp /usr/bin/qemu-aarch64-static /mnt/usr/bin/
sudo cp -r uconsole-rom /mnt/root/
sudo chroot /mnt /qemu-aarch64-static /bin/bash
# chroot 里：cd /root/uconsole-rom && ./customize.sh && exit

# 卸载并收缩
sudo umount /mnt/boot/firmware /mnt && sudo losetup -d /dev/loop0
```

## 打包成 ROM（备份 / 分发）

```bash
# 关机取卡插到电脑上，假设 SD 卡是 /dev/sdX（macOS 是 /dev/diskN，先 diskutil unmountDisk）
sudo dd if=/dev/sdX of=uconsole-aio.img bs=4M status=progress

# 收缩镜像（PiShrink：github.com/Drewsif/PiShrink）
sudo pishrink.sh -Z -a uconsole-aio.img      # -Z 压成 xz，-a 启用首次开机自动扩容

# 分发：刷回任意 ≥64GB 卡即可
# Raspberry Pi Imager → Use custom → 选 uconsole-aio.img.xz
```

## 第三方 / 手动安装清单

脚本会自动尝试 SDR++、meshtasticd、ollama；下面这些需要手动：

| 应用 | 来源 | 说明 |
|---|---|---|
| PICO-8 | lexaloffle.com | 付费，下载 ARM Linux 版解压即用 |
| TIC-80 | github.com/nesbox/TIC-80 | 免费开源，releases 里找 ARM 构建 |
| RetroPie | github.com/RetroPie | 跑它的 setup 脚本；与 apt 的 retroarch 二选一更省心 |
| SunVox | warmplace.ru | 免费，有 ARM Linux 版 |
| REAPER | reaper.fm | 有 aarch64 版，评估版免费 |
| M8 headless | github.com/DirtyWave/M8HeadlessFirmware | tracker 圈的 uConsole 经典玩法 |
| Metasploit | docs.metasploit.com | Ubuntu 源没有，用官方安装脚本 |
| Tailscale | tailscale.com/install.sh | 一行脚本 |
| 维基百科 ZIM | library.kiwix.org | 下 `wikipedia_zh_all_maxi_*.zim`，`kiwix-serve` 起服务 |
| tar1090 | github.com/wiedehopf/tar1090 | 给 dump1090 配个网页飞机地图 |

## 注意事项

- **内存**：CM4 只有 4GB——别装 GNOME（要桌面用 `--with-desktop` 装的 XFCE），zram 已默认启用。
- **散热**：全负载跑 hashcat/编译会顶到温控墙，论坛公认值得换好点的导热垫。
- **天线**：自带 WiFi 贴纸天线偏弱，做无线审计强烈建议改外置天线或 USB 网卡。
- **4G 模块**：`mmcli -m 0` 查状态，APN 用 `nmcli` 配。
- **合规**：渗透和 SDR 工具只能用于授权目标与当地法规允许的频段，别扫别人的网。
- **多卡策略**：很多人最后还是「一张全能 Ubuntu 卡 + 一张 Kali/Parrot 专用卡」，SD 卡热切换正是 uConsole 的设计亮点，不冲突。

## 目录结构

```
uconsole-rom/
├── README.md          # 本文件
├── customize.sh       # 主定制脚本（在 uConsole 上跑）
└── packages.d/        # 分类 apt 包清单，可自由增删
    ├── 10-base.list
    ├── 20-ops-net.list
    ├── 30-pentest.list
    ├── 40-sdr-radio.list
    ├── 50-mesh-comms.list
    ├── 60-games.list
    ├── 70-dev.list
    ├── 80-writing-knowledge.list
    ├── 90-music.list
    └── 95-llm.list
```
