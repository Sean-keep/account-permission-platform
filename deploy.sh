#!/bin/bash
# ============================================
# 人员账号与权限台账管理平台 - Ubuntu 一键部署脚本
# ============================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 打印带颜色的消息
info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# 检查是否为 root 用户
check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "请使用 root 用户或 sudo 运行此脚本"
    fi
}

# 检查系统
check_system() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [ "$ID" != "ubuntu" ]; then
            warn "当前系统不是 Ubuntu，可能不完全兼容"
        fi
        info "检测到系统: $PRETTY_NAME"
    else
        error "无法检测操作系统类型"
    fi
}

# 安装 Docker
install_docker() {
    if command -v docker &> /dev/null; then
        info "Docker 已安装: $(docker --version)"
    else
        info "正在安装 Docker..."
        apt-get update
        apt-get install -y apt-transport-https ca-certificates curl software-properties-common
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io
        systemctl enable docker
        systemctl start docker
        info "Docker 安装完成"
    fi
}

# 安装 Docker Compose
install_docker_compose() {
    if command -v docker-compose &> /dev/null || docker compose version &> /dev/null; then
        info "Docker Compose 已安装"
    else
        info "正在安装 Docker Compose..."
        apt-get install -y docker-compose-plugin
        info "Docker Compose 安装完成"
    fi
}

# 配置项目
setup_project() {
    local PROJECT_DIR="/opt/account-permission-platform"

    info "正在配置项目..."

    # 创建项目目录
    mkdir -p $PROJECT_DIR

    # 如果是当前目录部署
    if [ -f "./docker-compose.yml" ]; then
        cp -r . $PROJECT_DIR/
    else
        error "未找到项目文件，请在项目根目录运行此脚本"
    fi

    cd $PROJECT_DIR

    # 生成随机密码
    MYSQL_PASSWORD=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)
    JWT_SECRET=$(openssl rand -base64 32)

    # 创建环境配置
    cat > backend/.env << EOF
MYSQL_HOST=mysql
MYSQL_PORT=3306
MYSQL_USER=app_user
MYSQL_PASSWORD=${MYSQL_PASSWORD}
MYSQL_DATABASE=account_permission
JWT_SECRET_KEY=${JWT_SECRET}
JWT_EXPIRE_MINUTES=480
EOF

    info "项目配置完成"
    info "MySQL 密码: ${MYSQL_PASSWORD}"
    info "JWT 密钥: ${JWT_SECRET}"

    # 保存密码到文件
    cat > ${PROJECT_DIR}/.credentials << EOF
============================================
数据库配置
============================================
MySQL 密码: ${MYSQL_PASSWORD}
JWT 密钥: ${JWT_SECRET}
============================================
默认管理员账号
用户名: admin
密码: admin123
============================================
EOF

    chmod 600 ${PROJECT_DIR}/.credentials
    info "凭证已保存到: ${PROJECT_DIR}/.credentials"
}

# 启动服务
start_services() {
    local PROJECT_DIR="/opt/account-permission-platform"
    cd $PROJECT_DIR

    info "正在启动服务..."
    docker compose up -d --build

    info "等待服务启动..."
    sleep 10

    # 检查服务状态
    if docker compose ps | grep -q "Up"; then
        info "服务启动成功！"
    else
        error "服务启动失败，请检查日志: docker compose logs"
    fi
}

# 显示访问信息
show_info() {
    local IP=$(hostname -I | awk '{print $1}')

    echo ""
    echo "============================================"
    echo "  部署完成！"
    echo "============================================"
    echo ""
    echo "  访问地址:"
    echo "    前端: http://${IP}:3000"
    echo "    后端: http://${IP}:9000"
    echo ""
    echo "  默认管理员账号:"
    echo "    用户名: admin"
    echo "    密码: admin123"
    echo ""
    echo "  首次登录请立即修改密码！"
    echo ""
    echo "  凭证文件: /opt/account-permission-platform/.credentials"
    echo ""
    echo "  常用命令:"
    echo "    查看状态: cd /opt/account-permission-platform && docker compose ps"
    echo "    查看日志: cd /opt/account-permission-platform && docker compose logs -f"
    echo "    停止服务: cd /opt/account-permission-platform && docker compose down"
    echo "    重启服务: cd /opt/account-permission-platform && docker compose restart"
    echo ""
    echo "============================================"
}

# 主流程
main() {
    echo ""
    echo "============================================"
    echo "  人员账号与权限台账管理平台 - 安装程序"
    echo "============================================"
    echo ""

    check_root
    check_system
    install_docker
    install_docker_compose
    setup_project
    start_services
    show_info
}

# 运行主流程
main "$@"
