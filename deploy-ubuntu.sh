#!/bin/bash
# ============================================
# 人员账号与权限台账管理平台 - Ubuntu 一键部署脚本
# 不使用 Docker，纯原生部署
# ============================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 打印带颜色的消息
info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# 项目配置
PROJECT_DIR="/opt/account-permission-platform"
MYSQL_DATABASE="account_permission"
MYSQL_USER="app_user"
BACKEND_PORT=9000
FRONTEND_PORT=80

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

# 安装系统依赖
install_dependencies() {
    step "安装系统依赖..."

    apt-get update
    apt-get install -y \
        curl \
        wget \
        git \
        build-essential \
        libssl-dev \
        libffi-dev \
        python3-dev \
        python3-pip \
        python3-venv \
        software-properties-common \
        gnupg \
        lsb-release

    info "系统依赖安装完成"
}

# 安装 Python 3.10+
install_python() {
    step "检查 Python 版本..."

    if command -v python3 &> /dev/null; then
        PYTHON_VERSION=$(python3 --version | awk '{print $2}')
        info "Python 已安装: $PYTHON_VERSION"
    else
        info "正在安装 Python 3..."
        apt-get install -y python3 python3-pip python3-venv
    fi
}

# 安装 Node.js 18
install_nodejs() {
    step "检查 Node.js 版本..."

    if command -v node &> /dev/null; then
        NODE_VERSION=$(node --version)
        info "Node.js 已安装: $NODE_VERSION"
    else
        info "正在安装 Node.js 18..."
        curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
        apt-get install -y nodejs
        info "Node.js 安装完成: $(node --version)"
    fi
}

# 安装 MySQL 8.0
install_mysql() {
    step "检查 MySQL..."

    if command -v mysql &> /dev/null; then
        MYSQL_VERSION=$(mysql --version | awk '{print $6}' | tr -d ',')
        info "MySQL 已安装: $MYSQL_VERSION"
    else
        info "正在安装 MySQL 8.0..."

        # 设置 MySQL root 密码（非交互式）
        export DEBIAN_FRONTEND=noninteractive
        debconf-set-selections <<< 'mysql-server mysql-server/root_password password root'
        debconf-set-selections <<< 'mysql-server mysql-server/root_password_again password root'

        apt-get install -y mysql-server mysql-client

        # 启动 MySQL
        systemctl start mysql
        systemctl enable mysql

        info "MySQL 安装完成"
    fi
}

# 安装 Nginx
install_nginx() {
    step "检查 Nginx..."

    if command -v nginx &> /dev/null; then
        info "Nginx 已安装: $(nginx -v 2>&1 | awk -F/ '{print $2}')"
    else
        info "正在安装 Nginx..."
        apt-get install -y nginx
        systemctl start nginx
        systemctl enable nginx
        info "Nginx 安装完成"
    fi
}

# 配置 MySQL 数据库
setup_mysql() {
    step "配置 MySQL 数据库..."

    # 生成随机密码
    MYSQL_PASSWORD=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)
    JWT_SECRET=$(openssl rand -base64 32)

    # 创建数据库和用户
    mysql -u root -proot << EOF || mysql -u root << EOF
CREATE DATABASE IF NOT EXISTS ${MYSQL_DATABASE} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'localhost' IDENTIFIED BY '${MYSQL_PASSWORD}';
GRANT ALL PRIVILEGES ON ${MYSQL_DATABASE}.* TO '${MYSQL_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

    info "数据库配置完成"
    info "数据库名: ${MYSQL_DATABASE}"
    info "数据库用户: ${MYSQL_USER}"
    info "数据库密码: ${MYSQL_PASSWORD}"
}

# 部署项目文件
deploy_project() {
    step "部署项目文件..."

    # 创建项目目录
    mkdir -p ${PROJECT_DIR}

    # 复制项目文件
    if [ -f "./backend/requirements.txt" ]; then
        cp -r . ${PROJECT_DIR}/
    else
        error "未找到项目文件，请在项目根目录运行此脚本"
    fi

    info "项目文件部署完成"
}

# 配置后端
setup_backend() {
    step "配置后端..."

    cd ${PROJECT_DIR}/backend

    # 创建虚拟环境
    python3 -m venv venv
    source venv/bin/activate

    # 安装依赖
    pip install --upgrade pip
    pip install -r requirements.txt

    # 创建环境配置
    cat > .env << EOF
MYSQL_HOST=localhost
MYSQL_PORT=3306
MYSQL_USER=${MYSQL_USER}
MYSQL_PASSWORD=${MYSQL_PASSWORD}
MYSQL_DATABASE=${MYSQL_DATABASE}
JWT_SECRET_KEY=${JWT_SECRET}
JWT_EXPIRE_MINUTES=480
EOF

    # 初始化数据库
    python3 -c "
from app.models.base import Base, engine
from app.models import user, personnel, system, account, audit_log
Base.metadata.create_all(bind=engine)
print('数据库表初始化完成')
"

    deactivate

    info "后端配置完成"
}

# 构建前端
build_frontend() {
    step "构建前端..."

    cd ${PROJECT_DIR}/frontend

    # 安装依赖
    npm install

    # 构建生产版本
    npm run build

    # 复制构建产物
    mkdir -p /var/www/account-permission
    cp -r dist/* /var/www/account-permission/

    info "前端构建完成"
}

# 配置 systemd 服务
setup_systemd() {
    step "配置 systemd 服务..."

    # 创建后端服务
    cat > /etc/systemd/system/account-permission-backend.service << EOF
[Unit]
Description=Account Permission Platform Backend
After=network.target mysql.service

[Service]
Type=simple
User=root
WorkingDirectory=${PROJECT_DIR}/backend
EnvironmentFile=${PROJECT_DIR}/backend/.env
ExecStart=${PROJECT_DIR}/backend/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port ${BACKEND_PORT}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    # 重新加载 systemd
    systemctl daemon-reload

    # 启用并启动服务
    systemctl enable account-permission-backend
    systemctl start account-permission-backend

    info "systemd 服务配置完成"
}

# 配置 Nginx
setup_nginx() {
    step "配置 Nginx..."

    # 创建 Nginx 配置
    cat > /etc/nginx/sites-available/account-permission << EOF
server {
    listen ${FRONTEND_PORT};
    server_name _;

    root /var/www/account-permission;
    index index.html;

    # 前端路由（Vue Router history 模式）
    location / {
        try_files \$uri \$uri/ /index.html;
    }

    # 静态资源缓存
    location ~* \.(js|mjs|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # API 反向代理到后端
    location /api/ {
        proxy_pass http://127.0.0.1:${BACKEND_PORT}/api/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Content-Type \$content_type;
        proxy_set_header Content-Length \$content_length;
    }
}
EOF

    # 启用站点
    ln -sf /etc/nginx/sites-available/account-permission /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default

    # 测试并重启 Nginx
    nginx -t
    systemctl restart nginx

    info "Nginx 配置完成"
}

# 保存凭证
save_credentials() {
    step "保存部署凭证..."

    cat > ${PROJECT_DIR}/.credentials << EOF
============================================
人员账号与权限台账管理平台 - 部署凭证
============================================
部署时间: $(date)
项目目录: ${PROJECT_DIR}

数据库配置
--------------------------------------------
MySQL 主机: localhost
MySQL 端口: 3306
MySQL 用户: ${MYSQL_USER}
MySQL 密码: ${MYSQL_PASSWORD}
数据库名: ${MYSQL_DATABASE}

JWT 配置
--------------------------------------------
JWT 密钥: ${JWT_SECRET}
Token 过期时间: 480 分钟

默认管理员账号
--------------------------------------------
用户名: admin
密码: admin123

服务端口
--------------------------------------------
前端: ${FRONTEND_PORT}
后端: ${BACKEND_PORT}

访问地址
--------------------------------------------
前端: http://$(hostname -I | awk '{print $1}'):${FRONTEND_PORT}
后端 API: http://$(hostname -I | awk '{print $1}'):${BACKEND_PORT}/docs

常用命令
--------------------------------------------
查看后端状态: sudo systemctl status account-permission-backend
重启后端: sudo systemctl restart account-permission-backend
查看后端日志: sudo journalctl -u account-permission-backend -f
重启 Nginx: sudo systemctl restart nginx
查看 Nginx 日志: sudo tail -f /var/log/nginx/access.log

============================================
EOF

    chmod 600 ${PROJECT_DIR}/.credentials

    info "凭证已保存到: ${PROJECT_DIR}/.credentials"
}

# 验证部署
verify_deployment() {
    step "验证部署..."

    # 等待服务启动
    sleep 3

    # 检查后端服务
    if systemctl is-active --quiet account-permission-backend; then
        info "✅ 后端服务运行正常"
    else
        warn "⚠️ 后端服务启动异常，请检查日志"
    fi

    # 检查 Nginx
    if systemctl is-active --quiet nginx; then
        info "✅ Nginx 运行正常"
    else
        warn "⚠️ Nginx 启动异常，请检查配置"
    fi

    # 测试 API
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:${BACKEND_PORT}/docs | grep -q "200"; then
        info "✅ 后端 API 可访问"
    else
        warn "⚠️ 后端 API 访问异常"
    fi

    # 测试前端
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:${FRONTEND_PORT}/ | grep -q "200"; then
        info "✅ 前端页面可访问"
    else
        warn "⚠️ 前端页面访问异常"
    fi
}

# 显示部署信息
show_info() {
    local IP=$(hostname -I | awk '{print $1}')

    echo ""
    echo "============================================"
    echo "  🎉 部署完成！"
    echo "============================================"
    echo ""
    echo "  📍 访问地址:"
    echo "     前端: http://${IP}:${FRONTEND_PORT}"
    echo "     后端: http://${IP}:${BACKEND_PORT}/docs"
    echo ""
    echo "  👤 默认管理员账号:"
    echo "     用户名: admin"
    echo "     密码: admin123"
    echo ""
    echo "  ⚠️  首次登录请立即修改密码！"
    echo ""
    echo "  📄 凭证文件: ${PROJECT_DIR}/.credentials"
    echo ""
    echo "  🔧 常用命令:"
    echo "     查看后端状态: sudo systemctl status account-permission-backend"
    echo "     重启后端: sudo systemctl restart account-permission-backend"
    echo "     查看后端日志: sudo journalctl -u account-permission-backend -f"
    echo "     重启 Nginx: sudo systemctl restart nginx"
    echo ""
    echo "============================================"
}

# 主流程
main() {
    echo ""
    echo "============================================"
    echo "  人员账号与权限台账管理平台 - 安装程序"
    echo "  (Ubuntu 原生部署，不使用 Docker)"
    echo "============================================"
    echo ""

    check_root
    check_system
    install_dependencies
    install_python
    install_nodejs
    install_mysql
    install_nginx
    setup_mysql
    deploy_project
    setup_backend
    build_frontend
    setup_systemd
    setup_nginx
    save_credentials
    verify_deployment
    show_info
}

# 运行主流程
main "$@"
