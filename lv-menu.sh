#!/usr/bin/env bash
# =========================================================
# LinVis Reality + WARP 控制台 v1.0（霓虹绿 Hacker UI）
# 作者：LinVis（woaixiaoyur 专属定制）
# =========================================================

# === 颜色定义（霓虹绿） ===
GREEN="\e[92m"
RESET="\e[0m"

# ==== 标题 UI ====
show_banner() {
echo -e "${GREEN}"
cat << "EOF"
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃        LinVis Reality + WARP 控制台 v1.0 ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
EOF
echo -e "${RESET}"
}

# ==== 菜单 UI ====
show_menu() {
echo -e "${GREEN}
  1) 一键安装 / 重装 Reality + WARP
  2) 查看 Reality 节点（小火箭 / Clash）
  3) 重新生成 Reality（UUID / 公钥 / ShortID）
  4) 重启 Sing-box
  5) 查看出口 IP（WARP / 原生）
  6) 启用 WARP（全局模式）
  7) 启用 WARP（智能分流模式）⚡ 推荐
  8) 关闭 WARP
  9) 测试流媒体（Netflix / GPT / TikTok）
 10) 卸载所有（恢复到纯净系统）

  0) 退出控制台
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
请输入选项：${RESET}"
}

# ==== 功能函数 ====

install_or_reinstall() {
    bash <(curl -Ls https://raw.githubusercontent.com/woaixiaoyur/linvis/main/linvis.sh)
}

show_node() {
    if [ -f /usr/local/etc/sing-box/linvis_meta.conf ]; then
        echo -e "${GREEN}>>> Reality 节点如下：${RESET}"
        cat /usr/local/etc/sing-box/linvis_meta.conf
        echo
        echo -e "${GREEN}请重新执行 linvis.sh（或选项 1）查看完整节点链接。${RESET}"
    else
        echo -e "${GREEN}未检测到 Reality 元数据，请执行 1 重新安装。${RESET}"
    fi
}

regen_reality() {
    echo -e "${GREEN}>>> 重新生成 Reality 节点 ...${RESET}"
    bash <(curl -Ls https://raw.githubusercontent.com/woaixiaoyur/linvis/main/linvis.sh) regen
}

restart_singbox() {
    echo -e "${GREEN}>>> 重启 Sing-box ...${RESET}"
    systemctl restart sing-box
    systemctl status sing-box --no-pager
}

show_ip() {
    echo -e "${GREEN}当前出口IP：${RESET}"
    curl -s ipinfo.io
    echo
}

warp_global() {
    echo -e "${GREEN}>>> 启用 WARP 全局出口 ...${RESET}"
    wg-quick down wgcf 2>/dev/null
    sed -i 's#128.0.0.0/1, 0.0.0.0/1#0.0.0.0/0, ::/0#' /etc/wireguard/wgcf.conf
    wg-quick up wgcf
    echo -e "${GREEN}WARP 已切换为全局模式。${RESET}"
}

warp_split() {
    echo -e "${GREEN}>>> 启用 WARP 智能分流模式（推荐）...${RESET}"
    wg-quick down wgcf 2>/dev/null
    sed -i 's#0.0.0.0/0, ::/0#128.0.0.0/1, 0.0.0.0/1#' /etc/wireguard/wgcf.conf
    wg-quick up wgcf
    echo -e "${GREEN}WARP 已切换为分流模式。${RESET}"
}

warp_off() {
    echo -e "${GREEN}>>> 关闭 WARP ...${RESET}"
    wg-quick down wgcf
    echo -e "${GREEN}WARP 已关闭，使用机房原生出口。${RESET}"
}

test_stream() {
    echo -e "${GREEN}>>> 测试 Netflix ...${RESET}"
    curl -s https://www.netflix.com/title/80018499 -I | head -n 1

    echo -e "${GREEN}>>> 测试 ChatGPT ...${RESET}"
    curl -s https://chat.openai.com -I | head -n 1

    echo -e "${GREEN}>>> 测试 TikTok ...${RESET}"
    curl -s https://www.tiktok.com -I | head -n 1
}

uninstall_all() {
    echo -e "${GREEN}>>> 卸载 Reality + WARP + Sing-box ...${RESET}"
    systemctl stop sing-box
    systemctl disable sing-box
    rm -rf /usr/local/etc/sing-box
    rm -f /usr/local/bin/sing-box

    wg-quick down wgcf 2>/dev/null
    rm -rf /etc/wireguard
    rm -f /usr/local/bin/wgcf

    rm -f /usr/local/bin/linvis
    echo -e "${GREEN}卸载完成，系统已恢复干净。${RESET}"
}

# ==== 主入口 ====
while true; do
    clear
    show_banner
    show_menu
    read -rp "" opt
    case $opt in
        1) install_or_reinstall ;;
        2) show_node ;;
        3) regen_reality ;;
        4) restart_singbox ;;
        5) show_ip ;;
        6) warp_global ;;
        7) warp_split ;;
        8) warp_off ;;
        9) test_stream ;;
       10) uninstall_all ;;
        0) exit 0 ;;
        *) echo -e "${GREEN}无效输入，请重新选择。${RESET}" ;;
    esac
    echo
    read -rp "按 Enter 返回菜单..."
done
