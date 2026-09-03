#!/bin/bash
# ============================================
# 人员账号与权限台账管理平台 - Ubuntu 一键部署脚本
# 不使用 Docker，纯原生部署
# 版本: v6.0 - 修复执行顺序、保留用户配置
# ============================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 打印带颜色的消息
info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# 项目配置
PROJECT_DIR="/opt/account-permission-platform"
BACKEND_PORT=9000
FRONTEND_PORT=80
MAX_RETRY=3
RETRY_DELAY=5

# 是否使用外部数据库
USE_EXTERNAL_DB=false

# 检测是否有 systemd
HAS_SYSTEMD=false
if pidof systemd > /dev/null 2>&1 && [ "$(cat /proc/1/comm 2>/dev/null)" = "systemd" ]; then
    HAS_SYSTEMD=true
fi

# 带重试的命令执行
retry() {
    local cmd="$1"
    local desc="$2"
    local max_retry=${3:-$MAX_RETRY}
    local retry_delay=${4:-$RETRY_DELAY}
    local count=0

    while [ $count -lt $max_retry ]; do
        if eval "$cmd"; then
            return 0
        fi
        count=$((count + 1))
        if [ $count -lt $max_retry ]; then
            warn "${desc} 失败，${retry_delay}秒后重试 (${count}/${max_retry})..."
            sleep $retry_delay
        fi
    done

    error "${desc} 失败，已重试 ${max_retry} 次"
    return 1
}

# 检查是否为 root 用户
check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "请使用 root 用户或 sudo 运行此脚本"
        exit 1
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
        warn "无法检测操作系统类型，继续尝试..."
    fi

    if [ "$HAS_SYSTEMD" = false ]; then
        warn "未检测到 systemd，将使用直接进程管理"
    fi
}

# 检查端口是否被占用
check_port() {
    local port=$1
    if ss -tlnp 2>/dev/null | grep -q ":${port} " || netstat -tlnp 2>/dev/null | grep -q ":${port} "; then
        warn "端口 ${port} 已被占用"
        return 1
    fi
    return 0
}

# 安装系统依赖
install_dependencies() {
    step "安装系统依赖..."

    retry "apt-get update -y" "apt-get update" 3 10 || warn "apt-get update 失败"

    local packages=(
        curl wget git build-essential
        libssl-dev libffi-dev python3-dev
        python3-pip python3-venv
        software-properties-common gnupg lsb-release
        net-tools iproute2 mysql-client
    )

    for pkg in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $pkg "; then
            apt-get install -y "$pkg" 2>/dev/null || warn "安装 $pkg 失败"
        fi
    done

    info "系统依赖安装完成"
}

# 安装 Python 3
install_python() {
    step "检查 Python..."

    if command -v python3 &> /dev/null; then
        info "Python 已安装: $(python3 --version 2>&1 | awk '{print $2}')"
    else
        info "正在安装 Python 3..."
        retry "apt-get install -y python3 python3-pip python3-venv python3-dev" "安装 Python" || {
            error "Python 安装失败"
            return 1
        }
    fi
}

# 安装 Node.js 22+
install_nodejs() {
    step "检查 Node.js..."

    local REQUIRED_NODE_MAJOR=22

    if command -v node &> /dev/null; then
        local ver=$(node --version 2>/dev/null)
        local major=$(echo $ver | sed 's/v//' | cut -d. -f1)
        if [ "$major" -ge $REQUIRED_NODE_MAJOR ]; then
            info "Node.js 已安装: $ver"
            return 0
        else
            warn "Node.js 版本过低 ($ver)，需要 >= ${REQUIRED_NODE_MAJOR}"
        fi
    fi

    info "正在安装 Node.js ${REQUIRED_NODE_MAJOR}..."

    if curl -fsSL https://deb.nodesource.com/setup_${REQUIRED_NODE_MAJOR}.x -o /tmp/setup_node.sh 2>/dev/null; then
        bash /tmp/setup_node.sh 2>/dev/null
        apt-get install -y nodejs 2>/dev/null
    fi

    if ! command -v node &> /dev/null || [ "$(node -v 2>/dev/null | sed 's/v//' | cut -d. -f1)" -lt "$REQUIRED_NODE_MAJOR" ]; then
        warn "NodeSource 安装失败，尝试直接下载..."
        local NODE_VERSION="v22.16.0"
        local NODE_ARCH="linux-x64"
        [ "$(uname -m)" = "aarch64" ] && NODE_ARCH="linux-arm64"
        curl -fsSL "https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-${NODE_ARCH}.tar.xz" -o /tmp/node.tar.xz 2>/dev/null
        if [ -f /tmp/node.tar.xz ]; then
            tar -xf /tmp/node.tar.xz -C /usr/local --strip-components=1 2>/dev/null
            rm -f /tmp/node.tar.xz
        fi
    fi

    if command -v node &> /dev/null; then
        local ver=$(node --version)
        local major=$(echo $ver | sed 's/v//' | cut -d. -f1)
        if [ "$major" -ge $REQUIRED_NODE_MAJOR ]; then
            info "Node.js 安装完成: $ver"
        else
            error "Node.js 版本过低: $ver，需要 >= ${REQUIRED_NODE_MAJOR}"
            return 1
        fi
    else
        error "Node.js 安装失败"
        return 1
    fi
}

# 启动 MySQL
start_mysql() {
    if [ "$HAS_SYSTEMD" = true ]; then
        systemctl start mysql 2>/dev/null || systemctl start mysqld 2>/dev/null
    else
        if command -v mysqld_safe &> /dev/null; then
            mysqld_safe --user=mysql &
        else
            service mysql start 2>/dev/null || service mysqld start 2>/dev/null
        fi
    fi
    sleep 3
}

# 等待 MySQL
wait_for_mysql() {
    local max_wait=${1:-60}
    local count=0

    info "等待 MySQL 启动..."
    while [ $count -lt $max_wait ]; do
        if mysqladmin ping -u root --silent 2>/dev/null || mysql -u root -e "SELECT 1" &>/dev/null; then
            info "MySQL 已就绪"
            return 0
        fi
        sleep 2
        count=$((count + 2))
    done
    warn "MySQL 启动超时"
    return 1
}

# 安装 MySQL
install_mysql() {
    if [ "$USE_EXTERNAL_DB" = true ]; then
        info "使用外部数据库，跳过 MySQL 安装"
        return 0
    fi

    step "检查 MySQL..."

    if command -v mysql &> /dev/null; then
        info "MySQL 已安装"
        if ! mysqladmin ping -u root --silent 2>/dev/null; then
            start_mysql
            wait_for_mysql 30
        fi
        return 0
    fi

    info "正在安装数据库..."
    export DEBIAN_FRONTEND=noninteractive
    debconf-set-selections <<< 'mysql-server mysql-server/root_password password root' 2>/dev/null
    debconf-set-selections <<< 'mysql-server mysql-server/root_password_again password root' 2>/dev/null

    retry "apt-get install -y mysql-server mysql-client" "安装 MySQL" 2 10 || {
        warn "MySQL 安装失败，尝试 MariaDB..."
        retry "apt-get install -y mariadb-server mariadb-client" "安装 MariaDB" 2 10 || {
            error "数据库安装失败"
            return 1
        }
    }

    start_mysql
    wait_for_mysql 60
    info "数据库安装完成"
}

# 安装 Nginx
install_nginx() {
    step "检查 Nginx..."

    if command -v nginx &> /dev/null; then
        info "Nginx 已安装"
    else
        info "正在安装 Nginx..."
        retry "apt-get install -y nginx" "安装 Nginx" || {
            error "Nginx 安装失败"
            return 1
        }
    fi

    start_nginx 2>/dev/null
    info "Nginx 安装完成"
}

# 启动 Nginx
start_nginx() {
    if [ "$HAS_SYSTEMD" = true ]; then
        systemctl restart nginx
    else
        nginx -s stop 2>/dev/null
        sleep 1
        nginx 2>/dev/null
    fi
}

# 部署项目文件（第一步，复制文件但保留 .env）
deploy_project() {
    step "部署项目文件..."

    mkdir -p ${PROJECT_DIR}/backend
    mkdir -p ${PROJECT_DIR}/frontend

    # 备份现有 .env（目标目录）
    local env_backup=""
    if [ -f "${PROJECT_DIR}/backend/.env" ]; then
        env_backup=$(cat "${PROJECT_DIR}/backend/.env")
        info "已备份目标目录 .env"
    fi

    # 检查当前目录是否有 .env（用户配置的）
    local source_env=""
    if [ -f "./backend/.env" ]; then
        source_env=$(cat "./backend/.env")
        info "检测到当前目录 .env 配置"
    fi

    # 复制项目文件
    if [ -f "./backend/requirements.txt" ]; then
        # 复制后端（排除 venv 和 .env）
        rsync -av \
            --exclude='venv' \
            --exclude='.env' \
            --exclude='__pycache__' \
            --exclude='.git' \
            --exclude='node_modules' \
            ./backend/ ${PROJECT_DIR}/backend/ 2>/dev/null || cp -r ./backend/ ${PROJECT_DIR}/

        # 复制前端
        rsync -av \
            --exclude='node_modules' \
            --exclude='dist' \
            --exclude='.git' \
            ./frontend/ ${PROJECT_DIR}/frontend/ 2>/dev/null || cp -r ./frontend/ ${PROJECT_DIR}/

        # 复制其他文件
        [ -f "./deploy-ubuntu.sh" ] && cp ./deploy-ubuntu.sh ${PROJECT_DIR}/
        [ -f "./README.md" ] && cp ./README.md ${PROJECT_DIR}/
        [ -f "./docker-compose.yml" ] && cp ./docker-compose.yml ${PROJECT_DIR}/
    else
        error "未找到项目文件，请在项目根目录运行此脚本"
        return 1
    fi

    # 恢复 .env（优先使用当前目录的，其次使用备份的）
    if [ -n "$source_env" ]; then
        echo "$source_env" > "${PROJECT_DIR}/backend/.env"
        info "✅ 使用当前目录 .env 配置"
    elif [ -n "$env_backup" ]; then
        echo "$env_backup" > "${PROJECT_DIR}/backend/.env"
        info "✅ 恢复备份的 .env 配置"
    else
        info "未检测到 .env 配置，稍后将创建默认配置"
    fi

    info "项目文件部署完成"
}

# 检查是否使用外部数据库（在 deploy_project 之后调用）
check_external_db() {
    local env_file="${PROJECT_DIR}/backend/.env"

    if [ -f "$env_file" ]; then
        local host=$(grep -E "^MYSQL_HOST=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'" | xargs)
        local password=$(grep -E "^MYSQL_PASSWORD=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'" | xargs)
        local user=$(grep -E "^MYSQL_USER=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'" | xargs)

        # 如果配置了非空密码，且不是默认的占位符
        if [ -n "$password" ] && [ "$password" != "请修改为你的数据库密码" ]; then
            USE_EXTERNAL_DB=true
            info "检测到数据库配置:"
            info "  主机: $host"
            info "  用户: $user"
            return 0
        fi
    fi

    info "未检测到有效数据库配置，将使用本地 MySQL"
    return 1
}

# 配置本地 MySQL
setup_local_mysql() {
    if [ "$USE_EXTERNAL_DB" = true ]; then
        return 0
    fi

    step "配置本地 MySQL 数据库..."

    local MYSQL_PASSWORD=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)
    local JWT_SECRET=$(openssl rand -base64 32)

    local mysql_cmd=""

    if mysql -u root -e "SELECT 1" &>/dev/null; then
        mysql_cmd="mysql -u root"
    elif mysql -u root -proot -e "SELECT 1" &>/dev/null; then
        mysql_cmd="mysql -u root -proot"
    else
        error "无法连接 MySQL，请手动配置"
        return 1
    fi

    $mysql_cmd << EOF
CREATE DATABASE IF NOT EXISTS account_permission DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'app_user'@'localhost' IDENTIFIED BY '${MYSQL_PASSWORD}';
GRANT ALL PRIVILEGES ON account_permission.* TO 'app_user'@'localhost';
FLUSH PRIVILEGES;
EOF

    # 写入 .env
    cat > ${PROJECT_DIR}/backend/.env << EOF
MYSQL_HOST=localhost
MYSQL_PORT=3306
MYSQL_USER=app_user
MYSQL_PASSWORD=${MYSQL_PASSWORD}
MYSQL_DATABASE=account_permission
JWT_SECRET_KEY=${JWT_SECRET}
JWT_EXPIRE_MINUTES=480
EOF

    info "✅ 本地数据库配置完成"
    info "   用户: app_user"
    info "   密码: ${MYSQL_PASSWORD}"
}

# 配置后端
setup_backend() {
    step "配置后端..."

    cd ${PROJECT_DIR}/backend || {
        error "后端目录不存在"
        return 1
    }

    # 检查 .env 是否存在
    if [ ! -f ".env" ]; then
        error ".env 文件不存在"
        error "请先创建 ${PROJECT_DIR}/backend/.env 配置数据库连接"
        return 1
    fi

    # 显示当前配置
    info "当前数据库配置:"
    grep -E "^MYSQL_" .env | while read line; do
        info "  $line"
    done

    # 检查虚拟环境
    local need_rebuild=false

    if [ ! -d "venv" ]; then
        need_rebuild=true
        info "虚拟环境不存在，将创建"
    elif [ ! -f "venv/bin/activate" ] || [ ! -f "venv/bin/uvicorn" ]; then
        need_rebuild=true
        warn "虚拟环境不完整，将重建"
    elif ! venv/bin/python -c "import fastapi" &>/dev/null; then
        need_rebuild=true
        warn "虚拟环境缺少依赖，将重建"
    else
        info "虚拟环境已存在且完整"
    fi

    # 无论是否重建，都确保 bcrypt 版本正确
    source venv/bin/activate
    info "检查 bcrypt 版本..."
    pip install --force-reinstall bcrypt==4.0.1 2>/dev/null
    deactivate

    if [ "$need_rebuild" = true ]; then
        info "创建 Python 虚拟环境..."
        rm -rf venv
        python3 -m venv venv || {
            error "创建虚拟环境失败"
            return 1
        }

        source venv/bin/activate

        info "安装 Python 依赖..."
        pip install --upgrade pip 2>/dev/null
        retry "pip install -r requirements.txt" "安装 Python 依赖" 3 15 || {
            error "Python 依赖安装失败"
            deactivate
            return 1
        }

        # 确保 bcrypt 版本兼容
        pip install bcrypt==4.0.1 2>/dev/null

        deactivate
    fi

    # 初始化数据库
    info "初始化数据库..."
    source venv/bin/activate
    python init_db.py
    local init_result=$?
    deactivate

    if [ $init_result -ne 0 ]; then
        error "数据库初始化失败"
        error "请检查 .env 中的数据库配置"
        return 1
    fi

    info "✅ 后端配置完成"
}

# 构建前端
build_frontend() {
    step "构建前端..."

    cd ${PROJECT_DIR}/frontend || {
        error "前端目录不存在"
        return 1
    }

    # 检查是否需要重新构建
    if [ -d "dist" ] && [ -f "dist/index.html" ]; then
        info "前端已构建，跳过"
        mkdir -p /var/www/account-permission
        rm -rf /var/www/account-permission/*
        cp -r dist/* /var/www/account-permission/
        return 0
    fi

    # 安装依赖
    if [ ! -d "node_modules" ]; then
        info "安装前端依赖..."
        retry "npm install --legacy-peer-deps" "npm install" 3 20 || {
            warn "npm install 失败，尝试淘宝镜像..."
            retry "npm install --registry=https://registry.npmmirror.com --legacy-peer-deps" "npm install (镜像)" 3 20 || {
                error "前端依赖安装失败"
                return 1
            }
        }
    fi

    # 构建
    info "构建生产版本..."
    retry "npm run build" "npm run build" 2 10 || {
        error "前端构建失败"
        return 1
    }

    if [ ! -d "dist" ] || [ ! -f "dist/index.html" ]; then
        error "前端构建产物不存在"
        return 1
    fi

    mkdir -p /var/www/account-permission
    rm -rf /var/www/account-permission/*
    cp -r dist/* /var/www/account-permission/

    info "✅ 前端构建完成"
}

# 停止旧服务
stop_old_services() {
    if [ "$HAS_SYSTEMD" = true ]; then
        systemctl stop account-permission-backend 2>/dev/null
    fi

    if [ -f "${PROJECT_DIR}/.backend.pid" ]; then
        local pid=$(cat "${PROJECT_DIR}/.backend.pid")
        kill "$pid" 2>/dev/null
        rm -f "${PROJECT_DIR}/.backend.pid"
    fi

    pkill -f "uvicorn app.main:app.*${BACKEND_PORT}" 2>/dev/null
    sleep 1
}

# 配置服务
setup_services() {
    step "配置服务..."

    if [ ! -f "${PROJECT_DIR}/backend/venv/bin/uvicorn" ]; then
        error "后端虚拟环境不存在"
        return 1
    fi

    stop_old_services

    if [ "$HAS_SYSTEMD" = true ]; then
        setup_systemd_service
    else
        setup_startup_script
    fi
}

# 配置 systemd 服务
setup_systemd_service() {
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
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable account-permission-backend
    systemctl start account-permission-backend

    sleep 3
    if systemctl is-active --quiet account-permission-backend; then
        info "✅ 后端服务启动成功"
    else
        error "后端服务启动失败"
        error "查看日志: journalctl -u account-permission-backend -n 30"
        return 1
    fi
}

# 配置启动脚本
setup_startup_script() {
    cat > ${PROJECT_DIR}/start.sh << 'EOFSCRIPT'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKEND_DIR="${SCRIPT_DIR}/backend"
PID_FILE="${SCRIPT_DIR}/.backend.pid"
LOG_FILE="${SCRIPT_DIR}/backend.log"

start_backend() {
    if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
        echo "后端服务已在运行 (PID: $(cat $PID_FILE))"
        return 0
    fi

    pkill -f "uvicorn app.main:app" 2>/dev/null
    sleep 1

    echo "启动后端服务..."
    cd "$BACKEND_DIR"
    source venv/bin/activate
    nohup uvicorn app.main:app --host 0.0.0.0 --port 9000 > "$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"
    echo "后端服务已启动 (PID: $!)"
}

stop_backend() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "停止后端服务 (PID: $pid)..."
            kill "$pid"
        fi
        rm -f "$PID_FILE"
    fi
    pkill -f "uvicorn app.main:app" 2>/dev/null
    echo "后端服务已停止"
}

restart_backend() {
    stop_backend
    sleep 2
    start_backend
}

status_backend() {
    if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
        echo "后端服务运行中 (PID: $(cat $PID_FILE))"
    else
        echo "后端服务未运行"
    fi
}

case "$1" in
    start)   start_backend ;;
    stop)    stop_backend ;;
    restart) restart_backend ;;
    status)  status_backend ;;
    *)       echo "用法: $0 {start|stop|restart|status}" ;;
esac
EOFSCRIPT
    chmod +x ${PROJECT_DIR}/start.sh

    # 启动后端
    cd ${PROJECT_DIR}/backend
    source venv/bin/activate
    nohup uvicorn app.main:app --host 0.0.0.0 --port ${BACKEND_PORT} > ${PROJECT_DIR}/backend.log 2>&1 &
    echo $! > ${PROJECT_DIR}/.backend.pid
    deactivate

    sleep 3
    if kill -0 $(cat ${PROJECT_DIR}/.backend.pid) 2>/dev/null; then
        info "✅ 后端服务启动成功"
    else
        error "后端服务启动失败"
        error "查看日志: cat ${PROJECT_DIR}/backend.log"
        return 1
    fi
}

# 配置 Nginx
setup_nginx() {
    step "配置 Nginx..."

    if [ ! -f "/var/www/account-permission/index.html" ]; then
        error "前端构建产物不存在"
        return 1
    fi

    if ! check_port $FRONTEND_PORT; then
        rm -f /etc/nginx/sites-enabled/default
        pkill -f nginx 2>/dev/null
        sleep 1
    fi

    cat > /etc/nginx/sites-available/account-permission << EOF
server {
    listen ${FRONTEND_PORT};
    server_name _;

    root /var/www/account-permission;
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    location ~* \.(js|mjs|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

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

    ln -sf /etc/nginx/sites-available/account-permission /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default

    if nginx -t 2>&1; then
        start_nginx
        info "✅ Nginx 配置完成"
    else
        error "Nginx 配置测试失败"
        return 1
    fi
}

# 保存凭证
save_credentials() {
    step "保存部署凭证..."

    local IP=$(hostname -I | awk '{print $1}')

    cat > ${PROJECT_DIR}/.credentials << EOF
============================================
部署信息
============================================
访问地址: http://${IP}:${FRONTEND_PORT}
默认账号: admin / admin123
配置文件: ${PROJECT_DIR}/backend/.env
============================================
EOF

    chmod 600 ${PROJECT_DIR}/.credentials
    info "凭证已保存到: ${PROJECT_DIR}/.credentials"
}

# 验证部署
verify_deployment() {
    step "验证部署..."

    local all_ok=true

    if [ "$HAS_SYSTEMD" = true ]; then
        systemctl is-active --quiet account-permission-backend && info "✅ 后端服务运行正常" || { warn "⚠️  后端服务异常"; all_ok=false; }
    else
        [ -f "${PROJECT_DIR}/.backend.pid" ] && kill -0 $(cat "${PROJECT_DIR}/.backend.pid") 2>/dev/null && info "✅ 后端服务运行正常" || { warn "⚠️  后端服务异常"; all_ok=false; }
    fi

    pgrep -x nginx > /dev/null && info "✅ Nginx 运行正常" || { warn "⚠️  Nginx 异常"; all_ok=false; }

    sleep 2
    local api_code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:${BACKEND_PORT}/docs 2>/dev/null)
    [ "$api_code" = "200" ] && info "✅ 后端 API 可访问" || { warn "⚠️  后端 API 异常 (HTTP: $api_code)"; all_ok=false; }

    local front_code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:${FRONTEND_PORT}/ 2>/dev/null)
    [ "$front_code" = "200" ] && info "✅ 前端页面可访问" || { warn "⚠️  前端页面异常 (HTTP: $front_code)"; all_ok=false; }

    [ "$all_ok" = true ] && info "🎉 所有服务验证通过！" || warn "⚠️  部分服务异常，请根据提示排查"
}

# 显示部署信息
show_info() {
    local IP=$(hostname -I | awk '{print $1}')

    echo ""
    echo "============================================"
    echo "  部署完成！"
    echo "============================================"
    echo ""
    echo "  访问地址: http://${IP}:${FRONTEND_PORT}"
    echo "  默认账号: admin / admin123"
    echo ""
    echo "  配置文件: ${PROJECT_DIR}/backend/.env"
    echo ""

    if [ "$HAS_SYSTEMD" = false ]; then
        echo "  服务管理:"
        echo "    启动: ${PROJECT_DIR}/start.sh start"
        echo "    停止: ${PROJECT_DIR}/start.sh stop"
        echo "    重启: ${PROJECT_DIR}/start.sh restart"
        echo ""
    fi

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

    # 第一步：安装系统依赖
    install_dependencies || warn "系统依赖安装有问题"
    install_python || { error "Python 安装失败"; exit 1; }
    install_nodejs || warn "Node.js 安装有问题"
    install_nginx || warn "Nginx 安装有问题"

    # 第二步：部署项目文件（复制文件、保留 .env）
    deploy_project || { error "项目部署失败"; exit 1; }

    # 第三步：检查数据库配置（在文件部署之后）
    check_external_db

    # 第四步：安装和配置数据库
    install_mysql || { error "数据库安装失败"; exit 1; }
    setup_local_mysql || { error "数据库配置失败"; exit 1; }

    # 第五步：配置后端（使用 .env 中的配置）
    setup_backend || { error "后端配置失败"; exit 1; }

    # 第六步：构建前端
    build_frontend || warn "前端构建失败"

    # 第七步：配置和启动服务
    setup_services || error "服务配置失败"
    setup_nginx || warn "Nginx 配置有问题"

    save_credentials
    verify_deployment
    show_info
}

main "$@"
