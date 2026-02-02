#!/bin/bash

# ===============================
# 一键安装 Docker + Mailcow + Let's Encrypt
# 适用 Ubuntu 22
# ===============================

set -e

# 确认以 root 运行
if [ "$EUID" -ne 0 ]; then 
    echo "请使用 root 用户运行此脚本"
    exit 1
fi

# 输入域名
echo "======================================="
read -rp "请输入 Mailcow 使用的域名（例如 email.example.com）: " MAIL_DOMAIN

if [ -z "$MAIL_DOMAIN" ]; then
    echo "❌ 域名不能为空，退出安装"
    exit 1
fi

echo "你输入的域名是: $MAIL_DOMAIN"
echo "======================================="

# 更新系统
echo "更新系统..."
apt update && apt upgrade -y

# 安装依赖
echo "安装依赖..."
apt install -y curl git jq sudo software-properties-common apt-transport-https ca-certificates lsb-release socat

# 安装 Docker
echo "安装 Docker..."
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

# 安装 Docker Compose 插件
echo "安装 Docker Compose..."
DOCKER_COMPOSE_VER=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | jq -r .tag_name)
mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VER}/docker-compose-linux-x86_64" -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# 检查 Docker 安装
docker --version
docker compose version

# 创建 Mailcow 目录
echo "下载 Mailcow..."
MAILCOW_DIR=/opt/mailcow-dockerized
if [ -d "$MAILCOW_DIR" ]; then
    echo "Mailcow 目录已存在，删除旧目录..."
    rm -rf "$MAILCOW_DIR"
fi

git clone https://github.com/mailcow/mailcow-dockerized.git "$MAILCOW_DIR"
cd "$MAILCOW_DIR"

# 安装 jq（用于 generate_config.sh）
apt install -y jq

# 生成 Mailcow 配置
echo "生成 Mailcow 配置..."
export MAILCOW_HOSTNAME="$MAIL_DOMAIN"
./generate_config.sh

# 启用 Let's Encrypt
echo "启用 Let's Encrypt..."
sed -i "s/^# SSL_TYPE=.*/SSL_TYPE=letsencrypt/" mailcow.conf
sed -i "s/^# ENABLE_LETSENCRYPT=.*/ENABLE_LETSENCRYPT=y/" mailcow.conf
sed -i "s/^# LE_CERT_DOMAIN=.*/LE_CERT_DOMAIN=${MAIL_DOMAIN}/" mailcow.conf

# 拉取 Docker 镜像
echo "拉取 Mailcow Docker 镜像..."
docker compose pull

# 启动 Mailcow
echo "启动 Mailcow..."
docker compose up -d

echo "======================================="
echo "🎉 安装完成！"
echo "👉 请访问: https://${MAIL_DOMAIN}"
echo "👉 证书将通过 Let's Encrypt 自动申请（前提：域名已正确解析）"
echo "👉 默认账号：admin"
echo "👉 默认密码：moohoo"
echo "⚠️ 启动后请等待 2–3 分钟再登录，否则可能提示密码错误"
echo "======================================="

# --- 3 分钟后自动关闭 IPv6 ---
echo ""
echo "⏳ 3 分钟后将自动执行关闭 IPv6（Mailcow 官方 + Postfix 双保险）..."
sleep 180

MAILCOW_CONF="$MAILCOW_DIR/mailcow.conf"
POSTFIX_EXTRA="$MAILCOW_DIR/data/conf/postfix/extra.cf"

# 修改 mailcow.conf
if grep -q "^ENABLE_IPV6=" "$MAILCOW_CONF"; then
  sed -i 's/^ENABLE_IPV6=.*/ENABLE_IPV6=false/' "$MAILCOW_CONF"
  echo "✅ 已修改 ENABLE_IPV6=false"
else
  echo "ENABLE_IPV6=false" >> "$MAILCOW_CONF"
  echo "✅ 已追加 ENABLE_IPV6=false"
fi

# 写入 Postfix IPv4-only 配置
mkdir -p "$(dirname "$POSTFIX_EXTRA")"
cat > "$POSTFIX_EXTRA" <<EOF
inet_protocols = ipv4
smtp_address_preference = ipv4
EOF
echo "✅ 已写入 Postfix IPv4-only 配置"

# 重启 mailcow 以应用 IPv6 关闭
echo "⏳ 正在重启 mailcow（应用 IPv6 关闭）..."
docker compose down
docker compose up -d

echo "=============================="
echo "🎉 IPv6 已禁用完成（官方 + 双保险）"
echo "=============================="
