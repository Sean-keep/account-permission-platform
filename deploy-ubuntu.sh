#!/bin/bash
# ============================================
# 人员账号与权限台账管理平台 - Ubuntu 一键部署脚本
# 不使用 Docker，纯原生部署
# 版本: v4.0 - 支持外部数据库、无 systemd 环境
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
ENV_FILE=""

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

# 检查是否配置了外部数据库
check_external_db() {
    # 检查当前目录或项目目录下是否有 .env
    local env_files=(
        "./backend/.env"
        "${PROJECT_DIR}/backend/.env"
    )

    for env_file in "${env_files[@]}"; do
        if [ -f "$env_file" ]; then
            # 检查是否配置了 MYSQL_HOST
            local host=$(grep -E "^MYSQL_HOST=" "$env_file" | cut -d'=' -f2 | tr -d '"' | tr -d "'" | xargs)
            local password=$(grep -E "^MYSQL_PASSWORD=" "$env_file" | cut -d'=' -f2 | tr -d '"' | tr -d "'" | xargs)

            if [ -n "$host" ] && [ "$host" != "localhost" ] && [ "$host" != "127.0.0.1" ] && [ -n "$password" ]; then
                ENV_FILE="$env_file"
                USE_EXTERNAL_DB=true
                info "检测到外部数据库配置: $env_file"
                info "数据库主机: $host"
                return 0
            fi
        fi
    done

    return 1
}

# 配置外部数据库
setup_external_db() {
    step "配置外部数据库..."

    if [ -z "$ENV_FILE" ]; then
        error "未找到 .env 文件"
        return 1
    fi

    # 读取配置
    local host=$(grep -E "^MYSQL_HOST=" "$ENV_FILE" | cut -d'=' -f2 | tr -d '"' | tr -d "'" | xargs)
    local port=$(grep -E "^MYSQL_PORT=" "$ENV_FILE" | cut -d'=' -f2 | tr -d '"' | tr -d "'" | xargs)
    local user=$(grep -E "^MYSQL_USER=" "$ENV_FILE" | cut -d'=' -f2 | tr -d '"' | tr -d "'" | xargs)
    local password=$(grep -E "^MYSQL_PASSWORD=" "$ENV_FILE" | cut -d'=' -f2 | tr -d '"' | tr -d "'" | xargs)
    local database=$(grep -E "^MYSQL_DATABASE=" "$ENV_FILE" | cut -d'=' -f2 | tr -d '"' | tr -d "'" | xargs)

    port=${port:-3306}

    info "测试数据库连接..."
    info "  主机: $host:$port"
    info "  用户: $user"
    info "  数据库: $database"

    # 安装 mysql-client 用于测试
    apt-get install -y mysql-client 2>/dev/null || warn "mysql-client 安装失败"

    # 测试连接
    if mysql -h "$host" -P "$port" -u "$user" -p"$password" -e "SELECT 1" &>/dev/null; then
        info "✅ 数据库连接成功"
    else
        warn "无法连接到数据库，请检查配置"
        warn "确保数据库已创建并授权:"
        warn "  CREATE DATABASE $database DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
        warn "  GRANT ALL PRIVILEGES ON $database.* TO '$user'@'%';"
        warn ""
        warn "是否继续部署？(数据库表将在后端启动时自动创建)"
        read -p "继续? [Y/n]: " confirm
        if [ "$confirm" = "n" ] || [ "$confirm" = "N" ]; then
            return 1
        fi
    fi

    info "✅ 外部数据库配置完成"
}

# 安装系统依赖
install_dependencies() {
    step "安装系统依赖..."

    retry "apt-get update -y" "apt-get update" 3 10 || {
        warn "apt-get update 失败，尝试继续..."
    }

    local packages=(
        curl wget git build-essential
        libssl-dev libffi-dev python3-dev
        python3-pip python3-venv
        software-properties-common gnupg lsb-release
        net-tools iproute2
    )

    for pkg in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $pkg "; then
            apt-get install -y "$pkg" 2>/dev/null || warn "安装 $pkg 失败，继续..."
        fi
    done

    info "系统依赖安装完成"
}

# 安装 Python 3
install_python() {
    step "检查 Python..."

    if command -v python3 &> /dev/null; then
        local ver=$(python3 --version 2>&1 | awk '{print $2}')
        info "Python 已安装: $ver"
    else
        info "正在安装 Python 3..."
        retry "apt-get install -y python3 python3-pip python3-venv python3-dev" "安装 Python" || {
            error "Python 安装失败"
            return 1
        }
    fi

    python3 -m pip --version &>/dev/null || {
        info "安装 pip..."
        apt-get install -y python3-pip 2>/dev/null || warn "pip 安装失败"
    }
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

    # 方式1: NodeSource
    if curl -fsSL https://deb.nodesource.com/setup_${REQUIRED_NODE_MAJOR}.x -o /tmp/setup_node.sh 2>/dev/null; then
        bash /tmp/setup_node.sh 2>/dev/null
        apt-get install -y nodejs 2>/dev/null
    fi

    # 方式2: nvm
    if ! command -v node &> /dev/null || [ "$(node -v 2>/dev/null | sed 's/v//' | cut -d. -f1)" -lt "$REQUIRED_NODE_MAJOR" ]; then
        warn "NodeSource 安装失败，尝试使用 nvm..."
        export NVM_DIR="$HOME/.nvm"
        if [ ! -d "$NVM_DIR" ]; then
            curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash 2>/dev/null
        fi
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        nvm install ${REQUIRED_NODE_MAJOR} 2>/dev/null
        nvm use ${REQUIRED_NODE_MAJOR} 2>/dev/null
        ln -sf "$NVM_DIR/versions/node/v$(nvm version 2>/dev/null)/bin/node" /usr/local/bin/node 2>/dev/null
        ln -sf "$NVM_DIR/versions/node/v$(nvm version 2>/dev/null)/bin/npm" /usr/local/bin/npm 2>/dev/null
    fi

    # 方式3: 直接下载
    if ! command -v node &> /dev/null || [ "$(node -v 2>/dev/null | sed 's/v//' | cut -d. -f1)" -lt "$REQUIRED_NODE_MAJOR" ]; then
        warn "nvm 安装失败，尝试直接下载..."
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
            error "Node.js 版本仍然过低: $ver，需要 >= ${REQUIRED_NODE_MAJOR}"
            return 1
        fi
    else
        error "Node.js 安装失败"
        return 1
    fi
}

# 安装 MySQL（仅本地数据库时）
install_mysql() {
    if [ "$USE_EXTERNAL_DB" = true ]; then
        info "检测到外部数据库配置，跳过 MySQL 安装"
        return 0
    fi

    step "检查 MySQL..."

    if command -v mysql &> /dev/null; then
        info "MySQL 已安装"
        if ! mysqladmin ping -u root --silent 2>/dev/null && ! mysql -u root -e "SELECT 1" &>/dev/null; then
            start_mysql
            wait_for_mysql 30
        fi
        return 0
    fi

    info "正在安装数据库..."
    export DEBIAN_FRONTEND=noninteractive
    debconf-set-selections <<< 'mysql-server mysql-server/root_password password root' 2>/dev/null
    debconf-set-selections <<< 'mysql-server mysql-server/root_password_again password root' 2>/dev/null

    local installed=false
    retry "apt-get install -y mysql-server mysql-client" "安装 MySQL" 2 10 && installed=true

    if [ "$installed" = false ]; then
        warn "MySQL 安装失败，尝试 MariaDB..."
        retry "apt-get install -y mariadb-server mariadb-client" "安装 MariaDB" 2 10 && installed=true
    fi

    if [ "$installed" = false ]; then
        error "数据库安装失败"
        return 1
    fi

    start_mysql
    wait_for_mysql 60
    info "数据库安装完成"
}

# 启动 MySQL
start_mysql() {
    if [ "$HAS_SYSTEMD" = true ]; then
        systemctl start mysql 2>/dev/null || systemctl start mysqld 2>/dev/null
        systemctl enable mysql 2>/dev/null || systemctl enable mysqld 2>/dev/null
    else
        if command -v mysqld_safe &> /dev/null; then
            mysqld_safe --user=mysql &
        elif command -v mysqld &> /dev/null; then
            mysqld --user=mysql &
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
        if mysqladmin ping -u root --silent 2>/dev/null || mysql -u root -e "SELECT 1" &>/dev/null || mysql -u root -proot -e "SELECT 1" &>/dev/null; then
            info "MySQL 已就绪"
            return 0
        fi
        sleep 2
        count=$((count + 2))
    done
    warn "MySQL 启动超时"
    return 1
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
        nginx
    fi
}

# 停止 Nginx
stop_nginx() {
    if [ "$HAS_SYSTEMD" = true ]; then
        systemctl stop nginx 2>/dev/null
    else
        nginx -s stop 2>/dev/null
    fi
}

# 配置本地 MySQL 数据库
setup_local_mysql() {
    if [ "$USE_EXTERNAL_DB" = true ]; then
        return 0
    fi

    step "配置本地 MySQL 数据库..."

    local MYSQL_PASSWORD=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)
    local JWT_SECRET=$(openssl rand -base64 32)

    local mysql_cmd=""
    local connected=false

    if mysql -u root -e "SELECT 1" &>/dev/null; then
        mysql_cmd="mysql -u root"
        connected=true
    elif mysql -u root -proot -e "SELECT 1" &>/dev/null; then
        mysql_cmd="mysql -u root -proot"
        connected=true
    elif sudo mysql -e "SELECT 1" &>/dev/null 2>&1; then
        mysql_cmd="sudo mysql"
        connected=true
    fi

    if [ "$connected" = false ]; then
        warn "尝试修复 MySQL 认证..."
        mysql --socket=/var/run/mysqld/mysqld.sock -u root -e "
            ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'root';
            FLUSH PRIVILEGES;
        " 2>/dev/null
        if mysql -u root -proot -e "SELECT 1" &>/dev/null; then
            mysql_cmd="mysql -u root -proot"
            connected=true
        fi
    fi

    if [ "$connected" = false ]; then
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
}

# 部署项目文件
deploy_project() {
    step "部署项目文件..."

    mkdir -p ${PROJECT_DIR}

    if [ -f "./backend/requirements.txt" ]; then
        rsync -av --exclude='.git' --exclude='node_modules' --exclude='__pycache__' --exclude='venv' \
            ./ ${PROJECT_DIR}/ 2>/dev/null || cp -r . ${PROJECT_DIR}/
    else
        error "未找到项目文件，请在项目根目录运行此脚本"
        return 1
    fi

    info "项目文件部署完成"
}

# 配置后端
setup_backend() {
    step "配置后端..."

    cd ${PROJECT_DIR}/backend || {
        error "后端目录不存在"
        return 1
    }

    # 如果没有 .env，创建默认配置
    if [ ! -f ".env" ]; then
        warn ".env 文件不存在，创建默认配置..."
        local JWT_SECRET=$(openssl rand -base64 32)
        cat > .env << EOF
MYSQL_HOST=localhost
MYSQL_PORT=3306
MYSQL_USER=app_user
MYSQL_PASSWORD=your_password
MYSQL_DATABASE=account_permission
JWT_SECRET_KEY=${JWT_SECRET}
JWT_EXPIRE_MINUTES=480
EOF
        warn "请编辑 ${PROJECT_DIR}/backend/.env 配置数据库连接信息"
    fi

    # 清理旧的虚拟环境
    rm -rf venv

    # 创建虚拟环境
    info "创建 Python 虚拟环境..."
    python3 -m venv venv || {
        error "创建虚拟环境失败"
        return 1
    }

    source venv/bin/activate

    info "安装 Python 依赖..."
    pip install --upgrade pip 2>/dev/null || warn "pip 升级失败"
    retry "pip install -r requirements.txt" "安装 Python 依赖" 3 15 || {
        error "Python 依赖安装失败"
        deactivate
        return 1
    }

    deactivate

    info "✅ 后端配置完成"
}

# 构建前端
build_frontend() {
    step "构建前端..."

    cd ${PROJECT_DIR}/frontend || {
        error "前端目录不存在"
        return 1
    }

    rm -rf dist node_modules

    info "安装前端依赖..."
    retry "npm install --legacy-peer-deps" "npm install" 3 20 || {
        warn "npm install 失败，尝试淘宝镜像..."
        retry "npm install --registry=https://registry.npmmirror.com --legacy-peer-deps" "npm install (镜像)" 3 20 || {
            error "前端依赖安装失败"
            return 1
        }
    }

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

# 配置服务
setup_services() {
    step "配置服务..."

    if [ ! -f "${PROJECT_DIR}/backend/venv/bin/uvicorn" ]; then
        error "后端虚拟环境不存在"
        return 1
    fi

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

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl stop account-permission-backend 2>/dev/null
    systemctl enable account-permission-backend
    systemctl start account-permission-backend

    sleep 3
    if systemctl is-active --quiet account-permission-backend; then
        info "✅ systemd 服务配置完成"
    else
        warn "后端服务启动异常: journalctl -u account-permission-backend -n 20"
    fi
}

# 配置启动脚本
setup_startup_script() {
    cat > ${PROJECT_DIR}/start.sh << 'EOF'
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
    else
        echo "后端服务未运行"
    fi
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
EOF
    chmod +x ${PROJECT_DIR}/start.sh

    # 启动后端
    if [ -f "${PROJECT_DIR}/.backend.pid" ]; then
        kill $(cat "${PROJECT_DIR}/.backend.pid") 2>/dev/null
        rm -f "${PROJECT_DIR}/.backend.pid"
    fi

    cd ${PROJECT_DIR}/backend
    source venv/bin/activate
    nohup uvicorn app.main:app --host 0.0.0.0 --port ${BACKEND_PORT} > ${PROJECT_DIR}/backend.log 2>&1 &
    echo $! > ${PROJECT_DIR}/.backend.pid
    deactivate

    sleep 3
    if kill -0 $(cat ${PROJECT_DIR}/.backend.pid) 2>/dev/null; then
        info "✅ 后端服务启动完成"
    else
        warn "后端服务启动异常: cat ${PROJECT_DIR}/backend.log"
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
        warn "端口 ${FRONTEND_PORT} 被占用，尝试释放..."
        rm -f /etc/nginx/sites-enabled/default
        stop_nginx 2>/dev/null
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
人员账号与权限台账管理平台 - 部署凭证
============================================
部署时间: $(date)
项目目录: ${PROJECT_DIR}
访问地址: http://${IP}:${FRONTEND_PORT}
默认账号: admin / admin123

数据库配置
--------------------------------------------
$(cat ${PROJECT_DIR}/backend/.env 2>/dev/null | grep -E "^MYSQL_" || echo "请配置 .env")

常用命令
--------------------------------------------
EOF

    if [ "$HAS_SYSTEMD" = true ]; then
        echo "重启后端: sudo systemctl restart account-permission-backend" >> ${PROJECT_DIR}/.credentials
        echo "查看日志: sudo journalctl -u account-permission-backend -f" >> ${PROJECT_DIR}/.credentials
    else
        echo "启动后端: ${PROJECT_DIR}/start.sh start" >> ${PROJECT_DIR}/.credentials
        echo "停止后端: ${PROJECT_DIR}/start.sh stop" >> ${PROJECT_DIR}/.credentials
        echo "查看日志: cat ${PROJECT_DIR}/backend.log" >> ${PROJECT_DIR}/.credentials
    fi

    chmod 600 ${PROJECT_DIR}/.credentials
    info "凭证已保存到: ${PROJECT_DIR}/.credentials"
}

# 验证部署
verify_deployment() {
    step "验证部署..."

    local all_ok=true

    # 检查后端
    if [ "$HAS_SYSTEMD" = true ]; then
        systemctl is-active --quiet account-permission-backend && info "✅ 后端服务运行正常" || { warn "⚠️  后端服务异常"; all_ok=false; }
    else
        [ -f "${PROJECT_DIR}/.backend.pid" ] && kill -0 $(cat "${PROJECT_DIR}/.backend.pid") 2>/dev/null && info "✅ 后端服务运行正常" || { warn "⚠️  后端服务异常"; all_ok=false; }
    fi

    # 检查 Nginx
    pgrep -x nginx > /dev/null && info "✅ Nginx 运行正常" || { warn "⚠️  Nginx 异常"; all_ok=false; }

    # 测试 API
    sleep 2
    local api_code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:${BACKEND_PORT}/docs 2>/dev/null)
    [ "$api_code" = "200" ] && info "✅ 后端 API 可访问" || { warn "⚠️  后端 API 异常 (HTTP: $api_code)"; all_ok=false; }

    # 测试前端
    local front_code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:${FRONTEND_PORT}/ 2>/dev/null)
    [ "$front_code" = "200" ] && info "✅ 前端页面可访问" || { warn "⚠️  前端页面异常 (HTTP: $front_code)"; all_ok=false; }

    # 测试登录
    local login_result=$(curl -s http://localhost:${FRONTEND_PORT}/api/auth/login -X POST -H "Content-Type: application/json" -d '{"username":"admin","password":"admin123"}' 2>/dev/null)
    echo "$login_result" | grep -q '"code":200' && info "✅ 登录功能正常" || { warn "⚠️  登录测试失败"; all_ok=false; }

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
    echo "  凭证文件: ${PROJECT_DIR}/.credentials"
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

    # 检查是否使用外部数据库
    check_external_db

    # 安装基础依赖
    install_dependencies || warn "系统依赖安装有问题，继续..."
    install_python || { error "Python 安装失败"; exit 1; }
    install_nodejs || warn "Node.js 安装有问题"

    # 数据库
    if [ "$USE_EXTERNAL_DB" = true ]; then
        setup_external_db || { error "外部数据库配置失败"; exit 1; }
    else
        install_mysql || { error "数据库安装失败"; exit 1; }
        setup_local_mysql || { error "数据库配置失败"; exit 1; }
    fi

    # 部署
    deploy_project || { error "项目部署失败"; exit 1; }
    setup_backend || { error "后端配置失败"; exit 1; }

    # 前端构建
    build_frontend || warn "前端构建失败，可稍后手动构建"

    # 服务配置
    setup_services || warn "服务配置有问题"
    setup_nginx || warn "Nginx 配置有问题"

    save_credentials
    verify_deployment
    show_info
}

main "$@"
