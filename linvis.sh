#!/usr/bin/env bash
# =========================================================
# LinVis 一键 Reality + WARP（美国出口）自动安装脚本
#
# 作者：你自己（GitHub: woaixiaoyur）
# 功能：
#   - 自动安装依赖（curl / wget / jq / wireguard-tools 等）
#   - 自动安装 sing-box 最新版（官方脚本）
#   - 自动安装 & 配置 Cloudflare WARP（wgcf，全局代理，出口锁美国）
#   - 自动生成 VLESS Reality 节点（端口 4433，SNI: www.apple.com）
#   - 自动写入 config.json，重启 sing-box
#   - 自动开启 BBR + 网络优化 + 1G swap
#   - 自动打印：小火箭节点信息 + vless:// 链接 + Clash Meta 节点片段
#
# 使用模式：
#   你（中国） -> 美国 VPS(Reality) -> VPS 全局 WARP -> TikTok / YouTube / Netflix / GPT
#
# 适配：
#   - Debian / Ubuntu（推荐用美国机房 VPS）
#
# 一键使用示例（上传到 GitHub 后）：
#   bash <(curl -Ls https://raw.githubusercontent.com/woaixiaoyur/linvis/main/linvis.sh)
# =========================================================

set -e

SINGBOX_CONFIG="/usr/local/etc/sing-box/config.json"
META_INFO="/usr/local/etc/sing-box/linvis_meta.conf"

REALITY_PORT=4433
REALITY_SNI="www.apple.com"

color_green(){ echo -e "\e[32m$1\e[0m"; }
color_red(){ echo -e "\e[31m$1\e[0m"; }
color_yellow(){ echo -e "\e[33m$1\e[0m"; }
color_blue(){ echo -e "\e[36m$1\e[0m"; }

check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    color_red "❌ 请用 root 运行本脚本（先执行：sudo -i）。"
    exit 1
  fi
}

ascii_logo() {
cat << "EOF"
██╗     ██╗███╗   ██╗██╗   ██╗██╗███████╗
██║     ██║████╗  ██║██║   ██║██║██╔════╝
██║     ██║██╔██╗ ██║██║   ██║██║███████╗
██║     ██║██║╚██╗██║██║   ██║██║╚════██║
███████╗██║██║ ╚████║╚██████╔╝██║███████║
╚══════╝╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝╚══════╝
      LinVis Reality + WARP (US)
EOF
echo
}

install_deps(){
  color_blue ">>> 安装基础依赖（curl / wget / jq / wireguard-tools / resolvconf）..."
  if command -v apt >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt update -y || true
    apt install -y curl wget jq wireguard-tools resolvconf iproute2 gnupg lsb-release ca-certificates grep sed coreutils || true
  else
    color_red "❌ 未检测到 apt，本脚本目前只适配 Debian / Ubuntu 系。"
    exit 1
  fi
  color_green "✅ 基础依赖安装完成。"
}

install_singbox(){
  if command -v sing-box >/dev/null 2>&1; then
    color_green "✅ 已检测到 sing-box：$(command -v sing-box)"
  else
    color_blue ">>> 通过官方脚本安装 sing-box ..."
    curl -fsSL https://sing-box.app/install.sh | sh
  fi

  if systemctl list-unit-files | grep -q sing-box; then
    systemctl enable sing-box --now
    color_green "✅ sing-box 服务已启用并启动。"
  else
    color_yellow "⚠️ 未发现 sing-box systemd 服务（可能安装方式不同），请稍后手动检查。"
  fi

  mkdir -p "$(dirname "$SINGBOX_CONFIG")"
}

install_wgcf(){
  if command -v wgcf >/dev/null 2>&1; then
    color_green "✅ 已检测到 wgcf：$(command -v wgcf)"
    return
  fi

  color_blue ">>> 安装 wgcf（Cloudflare WARP CLI）..."
  local arch file_keyword download_url
  arch=$(uname -m)
  case "$arch" in
    x86_64|amd64) file_keyword="linux_amd64" ;;
    aarch64|arm64) file_keyword="linux_arm64" ;;
    *)
      color_red "❌ 暂不支持此 CPU 架构：$arch"
      exit 1
      ;;
  esac

  download_url=$(curl -fsSL https://api.github.com/repos/ViRb3/wgcf/releases/latest \
    | grep browser_download_url | grep "$file_keyword" | cut -d '"' -f4 | head -n1)

  if [ -z "$download_url" ]; then
    color_red "❌ 无法获取 wgcf 下载链接，请稍后重试。"
    exit 1
  fi

  curl -L "$download_url" -o /usr/local/bin/wgcf
  chmod +x /usr/local/bin/wgcf

  if ! wgcf -h >/dev/null 2>&1; then
    color_red "❌ wgcf 安装失败，请检查网络或稍后重试。"
    exit 1
  fi

  color_green "✅ wgcf 安装完成。"
}

setup_warp_wgcf(){
  install_wgcf

  cd /root

  if [ ! -f wgcf-account.toml ]; then
    color_blue ">>> 注册 Cloudflare WARP 账号（wgcf register）..."
    WGCF_ACCEPT_TOS=1 wgcf register || WGCF_ACCEPT_TOS=1 wgcf register
  else
    color_green "✅ 已存在 wgcf-account.toml，跳过注册。"
  fi

  if [ ! -f wgcf-profile.conf ]; then
    color_blue ">>> 生成 WARP WireGuard 配置（wgcf generate）..."
    wgcf generate
  else
    color_green "✅ 已存在 wgcf-profile.conf，跳过生成。"
  fi

  mkdir -p /etc/wireguard
  cp wgcf-profile.conf /etc/wireguard/wgcf.conf

  # 全局流量走 WARP
  sed -i 's#^AllowedIPs = .*#AllowedIPs = 0.0.0.0/0, ::/0#' /etc/wireguard/wgcf.conf || true

  color_blue ">>> 启动 WARP 接口（wgcf，全局出口）..."
  wg-quick down wgcf 2>/dev/null || true
  wg-quick up wgcf

  if command -v systemctl >/dev/null 2>&1; then
    systemctl enable wg-quick@wgcf --now || true
  fi

  color_green "✅ WARP (wgcf) 已启用为全局出口。"
}

generate_reality_config(){
  if ! command -v sing-box >/dev/null 2>&1; then
    color_red "❌ 未检测到 sing-box，请先安装 sing-box。"
    exit 1
  fi

  mkdir -p "$(dirname "$SINGBOX_CONFIG")"

  local UUID KEYS_JSON PRIV_KEY PUB_KEY SHORT_ID
  UUID=$(cat /proc/sys/kernel/random/uuid)

  color_blue ">>> 生成 Reality 密钥对..."
  KEYS_JSON=$(sing-box generate reality-keypair)
  PRIV_KEY=$(echo "$KEYS_JSON"  | grep -oP '"private_key"\s*:\s*"\K[^"]+')
  PUB_KEY=$(echo "$KEYS_JSON"   | grep -oP '"public_key"\s*:\s*"\K[^"]+')
  SHORT_ID=$(echo "$KEYS_JSON"  | grep -oP '"short_id"\s*:\s*"\K[^"]+')

  if [ -z "$PRIV_KEY" ] || [ -z "$PUB_KEY" ] || [ -z "$SHORT_ID" ]; then
    color_red "❌ Reality 密钥生成失败，请手动执行：sing-box generate reality-keypair 查看报错。"
    exit 1
  fi

  color_green "UUID     : $UUID"
  color_green "PubKey   : $PUB_KEY"
  color_green "ShortID  : $SHORT_ID"

  color_blue ">>> 写入 sing-box 配置：$SINGBOX_CONFIG"

  cat > "$SINGBOX_CONFIG" <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },

  "tcp_fast_open": true,
  "tcp_multi_path": true,

  "dns": {
    "servers": [
      { "address": "https://1.1.1.1/dns-query" },
      { "address": "local" }
    ],
    "strategy": "prefer_ipv4"
  },

  "inbounds": [
    {
      "type": "vless",
      "tag": "in-reality",
      "listen": "::",
      "listen_port": ${REALITY_PORT},
      "users": [
        {
          "uuid": "${UUID}",
          "flow": "xtls-rprx-vision",
          "encryption": "none"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${REALITY_SNI}",
        "reality": {
          "enabled": true,
          "private_key": "${PRIV_KEY}",
          "short_id": ["${SHORT_ID}"],
          "handshake": {
            "server": "${REALITY_SNI}",
            "server_port": 443
          }
        }
      },
      "multiplex": {
        "enabled": true
      },
      "sniff": true,
      "sniff_override_destination": true
    }
  ],

  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ],

  "route": {
    "auto_detect_interface": true,
    "final": "direct"
  }
}
EOF

  mkdir -p "$(dirname "$META_INFO")"
  cat > "$META_INFO" <<EOF
UUID=${UUID}
PUB_KEY=${PUB_KEY}
SHORT_ID=${SHORT_ID}
PORT=${REALITY_PORT}
SNI=${REALITY_SNI}
EOF

  if systemctl list-unit-files | grep -q sing-box; then
    systemctl restart sing-box || true
    color_green "✅ sing-box 配置已应用并重启。"
  else
    color_yellow "⚠️ 未发现 sing-box systemd 服务，请稍后手动确认。"
  fi
}

enable_bbr_and_optimize(){
  color_blue ">>> 写入 BBR + 网络优化参数..."

  cat <<EOF >> /etc/sysctl.conf

# === LinVis Reality + WARP 优化开始 ===
fs.file-max = 1000000

net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728

net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.ip_local_port_range = 1024 65535
# === LinVis Reality + WARP 优化结束 ===
EOF

  sysctl -p || true
  color_green "✅ BBR & sysctl 已应用（内核支持的话会启用 BBR）。"

  if ! grep -q "swap" /etc/fstab && [ -z "$(swapon --noheadings 2>/dev/null)" ]; then
    color_blue ">>> 未检测到 swap，创建 1G swap 提升稳定性..."
    fallocate -l 1G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=1024
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    color_green "✅ 已创建 1G swap。"
  else
    color_green "✅ 已存在 swap，跳过创建。"
  fi
}

get_current_ip(){
  if command -v curl >/dev/null 2>&1; then
    curl -s --max-time 8 https://ifconfig.me || echo "获取失败"
  else
    echo "未安装 curl"
  fi
}

print_result(){
  if [ ! -f "$META_INFO" ]; then
    color_red "❌ 找不到元数据文件：$META_INFO"
    return
  fi

  # shellcheck disable=SC1090
  source "$META_INFO"

  VPS_IP=$(get_current_ip)

  echo
  color_green "================= 当前 VPS 出口 IP（应为 WARP 美国） ================="
  echo "出口 IP：$VPS_IP"
  echo "（建议在浏览器用 iplocation.net / ipinfo.io 再确认是否在美国）"
  echo "======================================================================"
  echo

  VLESS_URL="vless://${UUID}@${VPS_IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=chrome&pbk=${PUB_KEY}&sid=${SHORT_ID}&type=tcp#LinVis-US-WARP"

  color_green "================= Shadowrocket / 小火箭 节点信息 ================="
  echo "名称：LinVis-US-WARP"
  echo "类型：VLESS"
  echo "地址：$VPS_IP"
  echo "端口：$PORT"
  echo "UUID：$UUID"
  echo "传输：tcp"
  echo "加密：none"
  echo "Flow：xtls-rprx-vision"
  echo "TLS：Reality"
  echo "SNI：$SNI"
  echo "Reality 公钥（pbk）：$PUB_KEY"
  echo "Reality ShortID：$SHORT_ID"
  echo
  echo "👉 小火箭 / Passwall 直接导入此链接："
  echo "$VLESS_URL"
  echo "==================================================================="
  echo

  color_green "================= Clash Meta / 软路由 节点片段 ==================="
  cat <<EOF
- name: "LinVis-US-WARP-Reality"
  type: vless
  server: $VPS_IP
  port: $PORT
  uuid: $UUID
  network: tcp
  tls: true
  servername: $SNI
  reality-opts:
    public-key: "$PUB_KEY"
    short-id: "$SHORT_ID"
  flow: xtls-rprx-vision
  udp: true
EOF
  echo "==================================================================="
  echo
  color_yellow "说明："
  echo "  - 小火箭：添加节点 → 粘贴 vless:// 链接 即可导入。"
  echo "  - OpenWrt / Passwall / Clash：把上面的节点片段加到节点列表里即可。"
  echo "  - TikTok / YouTube / GPT 等流量将走：VPS -> WARP 美国出口。"
  echo
}

main(){
  check_root
  ascii_logo
  color_green "===== LinVis 一键 Reality + WARP（美国出口）开始执行 ====="

  install_deps
  install_singbox
  setup_warp_wgcf
  generate_reality_config
  enable_bbr_and_optimize
  print_result

  color_green "===== 全部执行完成，可以在小火箭 / 软路由中添加节点使用了 ====="
}

main

