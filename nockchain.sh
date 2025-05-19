#!/bin/bash

# 启用错误追踪
set -e

# 输出错误信息并退出
error_exit() {
    echo -e "\n❌ 错误: $1"
    exit 1
}

# 自动部署函数，无需用户交互
auto_point() {
    echo -e "\n\n===================================================="
    echo -e "🔍 执行阶段: $1"
    echo -e "====================================================\n"
}

echo -e "\n💻 Nockchain 全自动部署脚本"

# 阶段1：检查并配置系统环境
auto_point "配置系统资源"
echo -e "\n💾 配置系统资源..."
ulimit -n 65535
echo "* soft nofile 65535" | sudo tee -a /etc/security/limits.conf
echo "* hard nofile 65535" | sudo tee -a /etc/security/limits.conf

# 阶段2：优化系统内存管理 - 不配置交换空间
auto_point "优化系统内存管理"
echo -e "\n💾 优化系统内存管理..."
# 调整系统对内存的使用倾向
echo "配置内存不足时的进程优先级..."
sudo sysctl -w vm.oom_kill_allocating_task=1  # 让触发OOM的进程首先被杀死
echo "vm.oom_kill_allocating_task=1" | sudo tee -a /etc/sysctl.conf  # 持久化设置

# 阶段3：安装基础依赖
auto_point "安装基础依赖"
echo -e "\n📦 安装依赖..."
sudo apt-get update && sudo apt install -y curl iptables build-essential git wget lz4 jq make gcc nano automake autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip

# 阶段4：安装 Node.js 和 PM2
auto_point "安装 Node.js 和 PM2"
echo -e "\n🔧 安装 Node.js 和 PM2..."
curl -fsSL https://deb.nodesource.com/setup_16.x | sudo -E bash -
sudo apt install -y nodejs
sudo npm install pm2 -g
node -v
npm -v
pm2 -v

# 阶段5：安装 Rust
auto_point "安装 Rust"
echo -e "\n🦀 安装 Rust..."
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source "$HOME/.cargo/env"
rustup default stable
rustup update stable
rustc --version
cargo --version

# 阶段6：克隆 nockchain 仓库
auto_point "克隆仓库"
echo -e "\n📁 检查并克隆 nockchain 仓库..."
if [ -d "$HOME/nockchain" ]; then
  echo "⚠️ 已存在 nockchain 目录: $HOME/nockchain"
  echo "自动删除并重新克隆..."
  rm -rf "$HOME/nockchain"
fi

echo "正在克隆仓库..."
cd $HOME
git clone https://github.com/zorp-corp/nockchain
echo "克隆完成"

cd $HOME/nockchain
echo "当前目录: $(pwd)"

# 阶段7：创建必要的目录结构
auto_point "创建目录结构"
echo -e "\n📁 创建必要的目录结构..."
mkdir -p ~/.nockapp/hoonc/pma
mkdir -p ~/.nockapp/hoonc/checkpoints
mkdir -p hoon/apps/dumbnet
mkdir -p assets

echo "目录结构已创建"

# 阶段8：安装 hoonc
auto_point "安装 hoonc"
echo -e "\n🔧 安装 hoonc..."
echo "当前目录: $(pwd)"
make install-hoonc
echo "hoonc 安装完成"

# 阶段9：构建项目
auto_point "构建 Nockchain"
echo -e "\n🔧 构建 Nockchain..."
echo "当前目录: $(pwd)"
make build
echo "构建完成"

# 阶段10：安装钱包
auto_point "安装钱包"
echo -e "\n🔧 安装钱包..."
make install-nockchain-wallet
echo "钱包安装完成"

# 阶段11：安装 Nockchain
auto_point "安装 Nockchain"
echo -e "\n🔧 安装 Nockchain..."
make install-nockchain
echo "Nockchain 安装完成"

# 阶段12：配置环境变量
auto_point "配置环境变量"
echo -e "\n✅ 配置环境变量..."
grep -q 'export PATH="$PATH:$HOME/nockchain/target/release"' ~/.bashrc || echo 'export PATH="$PATH:$HOME/nockchain/target/release"' >> ~/.bashrc
grep -q 'export RUST_LOG=info' ~/.bashrc || echo 'export RUST_LOG=info' >> ~/.bashrc
grep -q 'export RUST_BACKTRACE=1' ~/.bashrc || echo 'export RUST_BACKTRACE=1' >> ~/.bashrc
grep -q 'export MINIMAL_LOG_FORMAT=true' ~/.bashrc || echo 'export MINIMAL_LOG_FORMAT=true' >> ~/.bashrc
source ~/.bashrc
echo "环境变量已配置"

# 阶段13：生成钱包 - 直接从输出中提取公钥和私钥
auto_point "钱包生成"
echo -e "\n🔐 生成钱包..."

# 创建保存钱包信息的目录
WALLET_DIR="$HOME/.nockchain-wallet"
mkdir -p "$WALLET_DIR"
WALLET_INFO_FILE="$WALLET_DIR/wallet_info.txt"
chmod 700 "$WALLET_DIR"  # 设置只有所有者可访问

echo "执行钱包生成命令..."

# 执行命令并捕获输出
KEYGEN_OUTPUT=$(./target/release/nockchain-wallet keygen)
echo "$KEYGEN_OUTPUT"

# 提取日志中的助记词、公钥和私钥
SEED_PHRASE=$(echo "$KEYGEN_OUTPUT" | grep -o "wallet: memo: .*" | sed 's/wallet: memo: //' || echo "")
PUBLIC_KEY=$(echo "$KEYGEN_OUTPUT" | grep -o 'New Public Key.*' | grep -o '".*"' | tr -d '"' || echo "")
PRIVATE_KEY=$(echo "$KEYGEN_OUTPUT" | grep -o 'New Private Key.*' | grep -o '".*"' | tr -d '"' || echo "")

# 如果提取失败，尝试另一种提取方法
if [ -z "$PUBLIC_KEY" ]; then
    PUBLIC_KEY=$(echo "$KEYGEN_OUTPUT" | grep -o "public key: base58 .*" | sed 's/public key: base58 //' | tr -d '"' || echo "")
fi

if [ -z "$PRIVATE_KEY" ]; then
    PRIVATE_KEY=$(echo "$KEYGEN_OUTPUT" | grep -o "private key: base58 .*" | sed 's/private key: base58 //' | tr -d '"' || echo "")
fi

# 检查是否成功获取钱包信息
if [ -z "$PUBLIC_KEY" ] || [ -z "$PRIVATE_KEY" ]; then
    echo "⚠️ 警告：无法从输出中提取完整的钱包信息，请从上面的输出中手动获取。"

    # 尝试从输出中的明显位置获取
    echo "尝试从输出提取关键信息..."
    PUBLIC_KEY=$(echo "$KEYGEN_OUTPUT" | grep -A 2 "New Public Key" | tail -n 1 | tr -d '[:space:]' | tr -d '"' || echo "")
    PRIVATE_KEY=$(echo "$KEYGEN_OUTPUT" | grep -A 2 "New Private Key" | tail -n 1 | tr -d '[:space:]' | tr -d '"' || echo "")

    if [ -z "$PUBLIC_KEY" ] || [ -z "$PRIVATE_KEY" ]; then
        echo "⚠️ 仍然无法提取钱包信息。请查看上面的输出，手动复制公钥和私钥。"
    fi
fi

# 显示找到的信息
echo -e "\n找到的钱包信息:"
echo "助记词: $SEED_PHRASE"
echo "主公钥: $PUBLIC_KEY"
echo "主私钥: $PRIVATE_KEY"

# 保存钱包信息到文件
cat > "$WALLET_INFO_FILE" << EOF
======= NOCKCHAIN 钱包信息 - 请安全保管！=======
创建时间: $(date)
钱包助记词: $SEED_PHRASE
主公钥: $PUBLIC_KEY
主私钥: $PRIVATE_KEY
======= 警告：请勿共享此文件！=======
EOF

chmod 600 "$WALLET_INFO_FILE"  # 设置只有所有者可读写
echo -e "\n💼 钱包信息已保存到: $WALLET_INFO_FILE"

# 阶段14：更新 Makefile 挖矿公钥
auto_point "更新挖矿公钥"
echo -e "\n📄 写入 Makefile 挖矿公钥..."

if [ -z "$PUBLIC_KEY" ]; then
    echo "⚠️ 警告：未能提取公钥，请手动输入公钥："
    read -r PUBLIC_KEY
fi

if grep -q "MINING_PUBKEY" Makefile; then
    echo "Makefile 中已包含 MINING_PUBKEY"
    sed -i "s|^export MINING_PUBKEY :=.*$|export MINING_PUBKEY := $PUBLIC_KEY|" Makefile
    echo "已更新 MINING_PUBKEY"
else
    echo "Makefile 中未找到 MINING_PUBKEY，尝试直接添加"
    echo "export MINING_PUBKEY := $PUBLIC_KEY" >> Makefile
    echo "已添加 MINING_PUBKEY"
fi

# 阶段15：创建 PM2 配置文件
auto_point "创建 PM2 配置"
echo -e "\n📝 创建 PM2 配置文件..."
cat > ecosystem.config.js << EOF
module.exports = {
  apps : [{
    name: 'nockchain-leader',
    script: 'make',
    args: 'run-nockchain-leader',
    cwd: '${PWD}',
    watch: false,
    autorestart: true,
    log_date_format: 'YYYY-MM-DD HH:mm:ss',
    env: {
      'RUST_LOG': 'info',
      'PATH': process.env.PATH + ':${PWD}/target/release',
      'RUST_BACKTRACE': '1',
      'MINIMAL_LOG_FORMAT': 'true'
    },
    min_uptime: '5s',
    max_restarts: 10,
    restart_delay: 5000
  },
  {
    name: 'nockchain-follower',
    script: 'make',
    args: 'run-nockchain-follower',
    cwd: '${PWD}',
    watch: false,
    autorestart: true,
    log_date_format: 'YYYY-MM-DD HH:mm:ss',
    env: {
      'RUST_LOG': 'info',
      'PATH': process.env.PATH + ':${PWD}/target/release',
      'RUST_BACKTRACE': '1',
      'MINIMAL_LOG_FORMAT': 'true'
    },
    min_uptime: '5s',
    max_restarts: 10,
    restart_delay: 5000
  }]
};
EOF
echo "PM2 配置文件已创建: $(pwd)/ecosystem.config.js"

# 阶段16：自动启动节点
auto_point "启动节点"
echo -e "\n🚀 自动启动 Nockchain 节点..."
pm2 start ecosystem.config.js
pm2 save

# 设置开机自启
pm2_startup=$(pm2 startup | grep "sudo" | tail -n 1)
if [ ! -z "$pm2_startup" ]; then
  echo "执行 PM2 开机自启命令..."
  eval "$pm2_startup"
fi

echo "节点已启动，状态如下:"
pm2 list

echo -e "\n查看日志方法:"
echo "pm2 logs nockchain-leader    # 查看 leader 日志"
echo "pm2 logs nockchain-follower  # 查看 follower 日志"

# 阶段17：最终确认
auto_point "部署完成"
echo -e "\n🎉 Nockchain 部署完成！"
echo -e "\n📝 总结:"
echo -e "- 仓库目录: $HOME/nockchain"
echo -e "- 钱包公钥: $PUBLIC_KEY"
echo -e "- 钱包信息保存位置: $WALLET_INFO_FILE"
echo -e "- PM2 配置: $(pwd)/ecosystem.config.js"
echo -e "- 内存限制: 已移除，系统将使用可用的全部资源"
echo -e "- 环境变量: RUST_LOG=info, MINIMAL_LOG_FORMAT=true"
echo -e "- 节点状态: 已自动启动并配置为开机自启"

echo -e "\n⚠️  重要提示："
echo -e "- 请务必备份您的钱包信息文件: $WALLET_INFO_FILE"
echo -e "- 该文件包含助记词和私钥，请妥善保管！"

echo -e "\n全自动部署脚本执行完毕。"