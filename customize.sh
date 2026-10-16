#!/usr/bin/env bash
#
# customize.sh —— 把装好 Ubuntu 的 uConsole 一键定制成「全能 ROM」
#
# 用法（在 uConsole 上执行）：
#   sudo ./customize.sh                        # 装全部分类
#   sudo ./customize.sh --skip "music llm"     # 跳过某些分类
#   sudo ./customize.sh --only "base ops sdr"  # 只装指定分类
#   sudo ./customize.sh --with-desktop         # 基础镜像是 Server 版时加装 XFCE
#
# 分类名 = packages.d/ 文件名中间那段：base ops pentest sdr mesh games dev writing music llm
#
set -uo pipefail
cd "$(dirname "$(readlink -f "$0")")" || exit 1

# ---------- 参数解析 ----------
ONLY=""
SKIP=""
WITH_DESKTOP=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --only) ONLY="$2"; shift 2 ;;
    --skip) SKIP="$2"; shift 2 ;;
    --with-desktop) WITH_DESKTOP=1; shift ;;
    *) echo "未知参数: $1"; exit 1 ;;
  esac
done

[[ $EUID -eq 0 ]] || { echo "请用 sudo 运行"; exit 1; }
[[ -d packages.d ]] || { echo "找不到 packages.d 目录"; exit 1; }

# ---------- 环境信息 ----------
ARCH=$(dpkg --print-architecture)
CODENAME=$(. /etc/os-release && echo "${VERSION_CODENAME:-unknown}")
CORE="unknown"
grep -qi "Raspberry Pi Compute Module 5" /proc/device-tree/model 2>/dev/null && CORE="CM5"
grep -qi "Raspberry Pi Compute Module 4" /proc/device-tree/model 2>/dev/null && CORE="CM4"
grep -qi "clockworkpi" /proc/device-tree/compatible 2>/dev/null && [[ "$CORE" == "unknown" ]] && CORE="A-06?"

echo "==================================================="
echo " uConsole 全能 ROM 定制"
echo " 架构: $ARCH | Ubuntu: $CODENAME | 核心板: $CORE"
echo "==================================================="
[[ "$ARCH" == "arm64" ]] || echo "⚠️  不是 arm64，脚本是为 uConsole 写的，继续需谨慎"

export DEBIAN_FRONTEND=noninteractive
FAILED_PKGS=()

# ---------- apt 基础准备 ----------
apt-get update
apt-get install -y software-properties-common || true
add-apt-repository -y universe 2>/dev/null || true
apt-get update

# ---------- 工具函数 ----------
in_list() { local n="$1" l="$2"; [[ " $l " == *" $n "* ]]; }

install_pkg() {  # 支持 "a|b" 备选写法
  local spec="$1" p
  IFS='|' read -ra ALTS <<< "$spec"
  for p in "${ALTS[@]}"; do
    if apt-get install -y "$p" >/dev/null 2>&1; then
      echo "  ✓ $p"
      return 0
    fi
  done
  echo "  ✗ ${ALTS[*]}（装不上，已记录）"
  FAILED_PKGS+=("${ALTS[*]}")
}

install_category() {  # $1=分类名 $2=清单文件
  local name="$1" file="$2"
  if [[ -n "$ONLY" ]] && ! in_list "$name" "$ONLY"; then return 0; fi
  if in_list "$name" "$SKIP"; then echo "—— 跳过分类: $name"; return 0; fi
  echo
  echo "━━━ 分类 [$name] ($file) ━━━"
  # 支持行内注释：libretro-fceumm   # NES/红白机
  while read -r pkg; do install_pkg "$pkg"; done \
    < <(sed 's/#.*//; s/[[:space:]]//g' "$file" | grep -v '^$')
}

# ---------- 逐分类安装 ----------
install_category base    packages.d/10-base.list
install_category ops     packages.d/20-ops-net.list
install_category pentest packages.d/30-pentest.list
install_category sdr     packages.d/40-sdr-radio.list
install_category mesh    packages.d/50-mesh-comms.list
install_category games   packages.d/60-games.list
install_category dev     packages.d/70-dev.list
install_category writing packages.d/80-writing-knowledge.list
install_category music   packages.d/90-music.list
install_category llm     packages.d/95-llm.list

# ---------- 可选桌面（Server 版镜像才需要）----------
if [[ $WITH_DESKTOP -eq 1 ]]; then
  echo
  echo "━━━ 安装轻量桌面 XFCE（CM4 4GB 别碰 GNOME）━━━"
  install_pkg xubuntu-core
  install_pkg lightdm
fi

# ---------- 第三方应用（apt 里没有的）----------
want() {  # 第三方也走 --only/--skip 逻辑
  [[ -z "$ONLY" || " $ONLY " == *" $1 "* ]] && [[ " $SKIP " != *" $1 "* ]]
}

if want sdr; then
  echo; echo "━━━ 第三方: SDR++ ━━━"
  # SDR++ 官方 nightly 提供 Debian arm64 包；失败则提示手动装
  SDRPP_DEB=$(mktemp --suffix=.deb)
  if curl -fsSL -o "$SDRPP_DEB" "https://www.sdrpp.org/nightly/sdrpp_debian_aarch64.deb" \
     && apt-get install -y "$SDRPP_DEB"; then
    echo "  ✓ SDR++ 已装"
  else
    echo "  ✗ SDR++ 自动安装失败，去 https://www.sdrpp.org/ 手动下 nightly arm64 版"
  fi
  rm -f "$SDRPP_DEB"
fi

if want mesh; then
  echo; echo "━━━ 第三方: Meshtastic ━━━"
  # meshtasticd（Linux 原生守护进程，吃 SX1262 硬件）
  MESH_DEB=$(mktemp --suffix=.deb)
  MESH_URL=$(curl -fsSL https://api.github.com/repos/meshtastic/firmware/releases/latest \
    | grep -oE '"browser_download_url": *"[^"]*meshtasticd_[^"]*_arm64\.deb"' \
    | head -1 | cut -d'"' -f4)
  if [[ -n "${MESH_URL:-}" ]] && curl -fsSL -o "$MESH_DEB" "$MESH_URL" && apt-get install -y "$MESH_DEB"; then
    echo "  ✓ meshtasticd 已装（配置文件 /etc/meshtasticd/config.yaml，记得改 SPI/针脚）"
  else
    echo "  ✗ meshtasticd 自动安装失败，去 github.com/meshtastic/firmware/releases 手动下"
  fi
  rm -f "$MESH_DEB"
  # Python CLI
  sudo -u "${SUDO_USER:-root}" pip3 install --user meshtastic 2>/dev/null \
    || pip3 install meshtastic 2>/dev/null \
    || echo "  ✗ meshtastic CLI 装不上，稍后用 pipx install meshtastic"
fi

if want llm; then
  echo; echo "━━━ 第三方: Ollama（本地 LLM）━━━"
  if curl -fsSL https://ollama.com/install.sh | sh; then
    echo "  ✓ ollama 已装"
    echo "  拉个小模型试试（CM4 用 tinyllama；CM5 可以试 llama3.2:3b）："
    echo "    ollama pull tinyllama"
  else
    echo "  ✗ ollama 安装失败，见 https://ollama.com/download/linux"
  fi
fi

if want ops; then
  echo; echo "━━━ 第三方: Tailscale（可选组网）━━━"
  echo "  如需 Tailscale：curl -fsSL https://tailscale.com/install.sh | sh"
fi

# ---------- 系统级收尾配置 ----------
echo
echo "━━━ 系统收尾 ━━━"

# SSH 开机自启（运维终端的灵魂）
systemctl enable ssh 2>/dev/null && echo "  ✓ SSH 已设为开机自启"

# docker 组（如果装了 docker）
if command -v docker >/dev/null && [[ -n "${SUDO_USER:-}" ]]; then
  usermod -aG docker "$SUDO_USER" && echo "  ✓ $SUDO_USER 已加入 docker 组"
fi

# wireshark 抓包权限
if dpkg -l wireshark-common >/dev/null 2>&1 && [[ -n "${SUDO_USER:-}" ]]; then
  dpkg-reconfigure -f noninteractive wireshark-common 2>/dev/null || true
  usermod -aG wireshark "$SUDO_USER" && echo "  ✓ $SUDO_USER 已加入 wireshark 组"
fi

# SDR udev 规则生效
[[ -f /etc/udev/rules.d/rtl-sdr.rules || -f /lib/udev/rules.d/60-librtlsdr0.rules ]] \
  && udevadm control --reload-rules 2>/dev/null && echo "  ✓ SDR udev 规则已刷新"

# 清理，给镜像瘦身
apt-get clean
rm -rf /var/lib/apt/lists/*
echo "  ✓ apt 缓存已清理"

echo
echo "==================================================="
echo " 完成！"
if [[ ${#FAILED_PKGS[@]} -gt 0 ]]; then
  echo " 装不上的包（稍后手动处理）："
  printf '   - %s\n' "${FAILED_PKGS[@]}"
fi
echo
echo " 建议下一步："
echo "   1. reboot 验证各分类应用"
echo "   2. 关机取卡，用 dd + PiShrink 备份成 uconsole-aio.img"
echo "      （见 README.md 的「打包成 ROM」一节）"
echo "==================================================="
