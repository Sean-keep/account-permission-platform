#!/bin/bash
# ============================================
# 人员账号与权限台账管理平台 - Ubuntu 一键部署脚本
# 不使用 Docker，纯原生部署
# 版本: v3.0 - 支持无 systemd 环境（WSL/容器）
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
MYSQL_DATABASE="account_permission"
MYSQL_USER="app_user"
BACKEND_PORT=9000
FRONTEND_PORT=80
MAX_RETRY=3
RETRY_DELAY=5

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

# 等待 MySQL 就绪
wait_for_mysql() {
    local max_wait=${1:-60}
    local count=0

    info "等待 MySQL 启动..."
    while [ $count -lt $max_wait ]; do
        # 尝试多种方式检测
        if mysqladmin ping -u root --silent 2>/dev/null; then
            info "MySQL 已就绪"
            return 0
        fi
        if mysql -u root -e "SELECT 1" &>/dev/null; then
            info "MySQL 已就绪"
            return 0
        fi
        if mysql -u root -proot -e "SELECT 1" &>/dev/null; then
            info "MySQL 已就绪"
            return 0
        fi
        sleep 2
        count=$((count + 2))
    done

    warn "MySQL 启动超时，尝试继续..."
    return 1
}

# 启动 MySQL（兼容无 systemd）
start_mysql() {
    if [ "$HAS_SYSTEMD" = true ]; then
        systemctl start mysql 2>/dev/null || systemctl start mysqld 2>/dev/null
        systemctl enable mysql 2>/dev/null || systemctl enable mysqld 2>/dev/null
    else
        # 无 systemd 时直接启动
        if command -v mysqld_safe &> /dev/null; then
            mysqld_safe --user=mysql &
        elif command -v mysqld &> /dev/null; then
            mysqld --user=mysql &
        else
            # 尝试通过 service 命令
            service mysql start 2>/dev/null || service mysqld start 2>/dev/null
        fi
    fi
    sleep 3
}

# 启动 Nginx（兼容无 systemd）
start_nginx() {
    if [ "$HAS_SYSTEMD" = true ]; then
        systemctl restart nginx
    else
        # 无 systemd 时直接启动
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

# 安装系统依赖
install_dependencies() {
    step "安装系统依赖..."

    # 更新 apt（允许失败）
    retry "apt-get update -y" "apt-get update" 3 10 || {
        warn "apt-get update 失败，尝试继续..."
    }

    # 安装基础依赖
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

    # 确保 pip 可用
    python3 -m pip --version &>/dev/null || {
        info "安装 pip..."
        apt-get install -y python3-pip 2>/dev/null || warn "pip 安装失败"
    }
}

# 安装 Node.js 22+（Vite 8 需要）
install_nodejs() {
    step "检查 Node.js..."

    # 项目需要 Node.js >= 22（Vite 8 + TypeScript 6）
    local REQUIRED_NODE_MAJOR=22

    # 检查已有版本
    if command -v node &> /dev/null; then
        local ver=$(node --version 2>/dev/null)
        local major=$(echo $ver | sed 's/v//' | cut -d. -f1)
        if [ "$major" -ge $REQUIRED_NODE_MAJOR ]; then
            info "Node.js 已安装: $ver"
            return 0
        else
            warn "Node.js 版本过低 ($ver)，需要 >= ${REQUIRED_NODE_MAJOR}"
            warn "正在升级 Node.js..."
        fi
    fi

    info "正在安装 Node.js ${REQUIRED_NODE_MAJOR}..."

    # 方式1: NodeSource（推荐）
    if curl -fsSL https://deb.nodesource.com/setup_${REQUIRED_NODE_MAJOR}.x -o /tmp/setup_node.sh 2>/dev/null; then
        bash /tmp/setup_node.sh 2>/dev/null
        apt-get install -y nodejs 2>/dev/null
    fi

    # 方式2: 使用 nvm 安装
    if ! command -v node &> /dev/null || [ "$(node -v | sed 's/v//' | cut -d. -f1)" -lt "$REQUIRED_NODE_MAJOR" ]; then
        warn "NodeSource 安装失败，尝试使用 nvm..."
        export NVM_DIR="$HOME/.nvm"
        if [ ! -d "$NVM_DIR" ]; then
            curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash 2>/dev/null
        fi
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        nvm install ${REQUIRED_NODE_MAJOR} 2>/dev/null
        nvm use ${REQUIRED_NODE_MAJOR} 2>/dev/null
        # 创建全局链接
        ln -sf "$NVM_DIR/versions/node/v$(nvm version)/bin/node" /usr/local/bin/node 2>/dev/null
        ln -sf "$NVM_DIR/versions/node/v$(nvm version)/bin/npm" /usr/local/bin/npm 2>/dev/null
        ln -sf "$NVM_DIR/versions/node/v$(nvm version)/bin/npx" /usr/local/bin/npx 2>/dev/null
    fi

    # 方式3: 直接下载二进制
    if ! command -v node &> /dev/null || [ "$(node -v | sed 's/v//' | cut -d. -f1)" -lt "$REQUIRED_NODE_MAJOR" ]; then
        warn "nvm 安装失败，尝试直接下载二进制..."
        local NODE_VERSION="v22.16.0"
        local NODE_ARCH="linux-x64"
        if [ "$(uname -m)" = "aarch64" ]; then
            NODE_ARCH="linux-arm64"
        fi
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
            error "请手动安装: https://nodejs.org/"
            return 1
        fi
    else
        error "Node.js 安装失败，请手动安装 Node.js >= ${REQUIRED_NODE_MAJOR}"
        error "下载地址: https://nodejs.org/"
        return 1
    fi
}

# 安装 MySQL
install_mysql() {
    step "检查 MySQL..."

    # 检查是否已安装
    if command -v mysql &> /dev/null; then
        info "MySQL 已安装: $(mysql --version 2>/dev/null | awk '{print $6}' | tr -d ',')"
        # 确保 MySQL 正在运行
        if ! mysqladmin ping -u root --silent 2>/dev/null && ! mysql -u root -e "SELECT 1" &>/dev/null; then
            info "启动 MySQL..."
            start_mysql
            wait_for_mysql 30
        fi
        return 0
    fi

    info "正在安装数据库..."

    # 非交互式安装
    export DEBIAN_FRONTEND=noninteractive

    # 预设 root 密码
    debconf-set-selections <<< 'mysql-server mysql-server/root_password password root' 2>/dev/null
    debconf-set-selections <<< 'mysql-server mysql-server/root_password_again password root' 2>/dev/null

    # 尝试安装 MySQL
    local installed=false
    retry "apt-get install -y mysql-server mysql-client" "安装 MySQL" 2 10 && installed=true

    # MySQL 失败则尝试 MariaDB
    if [ "$installed" = false ]; then
        warn "MySQL 安装失败，尝试 MariaDB..."
        retry "apt-get install -y mariadb-server mariadb-client" "安装 MariaDB" 2 10 && installed=true
    fi

    if [ "$installed" = false ]; then
        error "数据库安装失败"
        return 1
    fi

    # 启动数据库
    start_mysql
    wait_for_mysql 60

    info "数据库安装完成"
}

# 安装 Nginx
install_nginx() {
    step "检查 Nginx..."

    if command -v nginx &> /dev/null; then
        info "Nginx 已安装: $(nginx -v 2>&1 | awk -F/ '{print $2}')"
    else
        info "正在安装 Nginx..."
        retry "apt-get install -y nginx" "安装 Nginx" || {
            error "Nginx 安装失败"
            return 1
        }
    fi

    # 确保 Nginx 运行
    start_nginx 2>/dev/null

    info "Nginx 安装完成"
}

# 配置 MySQL 数据库
setup_mysql() {
    step "配置 MySQL 数据库..."

    # 生成随机密码
    MYSQL_PASSWORD=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)
    JWT_SECRET=$(openssl rand -base64 32)

    # 尝试多种方式连接 MySQL
    local mysql_cmd=""
    local connected=false

    # 方式1: root 无密码
    if mysql -u root -e "SELECT 1" &>/dev/null; then
        mysql_cmd="mysql -u root"
        connected=true
        info "MySQL 连接方式: root 无密码"
    fi

    # 方式2: root/root
    if [ "$connected" = false ] && mysql -u root -proot -e "SELECT 1" &>/dev/null; then
        mysql_cmd="mysql -u root -proot"
        connected=true
        info "MySQL 连接方式: root/root"
    fi

    # 方式3: sudo mysql
    if [ "$connected" = false ]; then
        local sudo_mysql=$(sudo mysql -e "SELECT 1" 2>/dev/null)
        if [ $? -eq 0 ]; then
            mysql_cmd="sudo mysql"
            connected=true
            info "MySQL 连接方式: sudo mysql"
        fi
    fi

    # 方式4: 尝试修复认证
    if [ "$connected" = false ]; then
        warn "尝试修复 MySQL 认证..."

        # 尝试用 auth_socket 方式连接并修改密码
        if command -v mysql &> /dev/null; then
            # 尝试直接通过 socket
            mysql --socket=/var/run/mysqld/mysqld.sock -u root -e "
                ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'root';
                FLUSH PRIVILEGES;
            " 2>/dev/null

            if mysql -u root -proot -e "SELECT 1" &>/dev/null; then
                mysql_cmd="mysql -u root -proot"
                connected=true
                info "MySQL 连接方式: root/root (已修复)"
            fi
        fi
    fi

    # 方式5: 尝试无密码连接（某些安装可能没有设密码）
    if [ "$connected" = false ]; then
        # 重启 MySQL 并跳过权限
        warn "尝试跳过权限验证启动 MySQL..."
        if [ "$HAS_SYSTEMD" = true ]; then
            systemctl stop mysql 2>/dev/null || systemctl stop mysqld 2>/dev/null
        else
            killall mysqld 2>/dev/null
            sleep 2
        fi

        mysqld_safe --skip-grant-tables &
        sleep 5

        mysql -u root -e "
            FLUSH PRIVILEGES;
            ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'root';
            FLUSH PRIVILEGES;
        " 2>/dev/null

        # 重启正常模式
        killall mysqld 2>/dev/null
        sleep 3
        start_mysql
        wait_for_mysql 30

        if mysql -u root -proot -e "SELECT 1" &>/dev/null; then
            mysql_cmd="mysql -u root -proot"
            connected=true
            info "MySQL 连接方式: root/root (已修复)"
        fi
    fi

    if [ "$connected" = false ]; then
        error "无法连接 MySQL"
        error ""
        error "请手动执行以下步骤:"
        error "1. sudo mysql"
        error "2. ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'root';"
        error "3. FLUSH PRIVILEGES;"
        error "4. 重新运行此脚本"
        return 1
    fi

    # 创建数据库和用户
    $mysql_cmd << EOF
CREATE DATABASE IF NOT EXISTS ${MYSQL_DATABASE} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'localhost' IDENTIFIED BY '${MYSQL_PASSWORD}';
GRANT ALL PRIVILEGES ON ${MYSQL_DATABASE}.* TO '${MYSQL_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

    if [ $? -eq 0 ]; then
        info "✅ 数据库配置完成"
        info "   数据库名: ${MYSQL_DATABASE}"
        info "   数据库用户: ${MYSQL_USER}"
        info "   数据库密码: ${MYSQL_PASSWORD}"
    else
        error "数据库配置失败"
        return 1
    fi
}

# 部署项目文件
deploy_project() {
    step "部署项目文件..."

    # 创建项目目录
    mkdir -p ${PROJECT_DIR}

    # 复制项目文件
    if [ -f "./backend/requirements.txt" ]; then
        # 排除不需要的文件
        rsync -av --exclude='.git' --exclude='node_modules' --exclude='__pycache__' --exclude='venv' --exclude='.env' \
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

    # 清理旧的虚拟环境
    if [ -d "venv" ]; then
        warn "发现旧的虚拟环境，清理中..."
        rm -rf venv
    fi

    # 创建虚拟环境
    info "创建 Python 虚拟环境..."
    python3 -m venv venv || {
        error "创建虚拟环境失败"
        return 1
    }

    source venv/bin/activate

    # 安装依赖（带重试）
    info "安装 Python 依赖..."
    pip install --upgrade pip 2>/dev/null || warn "pip 升级失败，继续..."
    retry "pip install -r requirements.txt" "安装 Python 依赖" 3 15 || {
        error "Python 依赖安装失败"
        deactivate
        return 1
    }

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
    info "初始化数据库表..."
    python3 -c "
from app.models.base import Base, engine
from app.models import user, personnel, system, account, audit_log
Base.metadata.create_all(bind=engine)
print('数据库表初始化完成')
" || {
        warn "数据库表初始化失败，可能需要手动初始化"
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

    # 清理旧的构建
    rm -rf dist node_modules

    # 安装依赖（带重试）
    info "安装前端依赖..."
    retry "npm install --legacy-peer-deps" "npm install" 3 20 || {
        # 尝试使用淘宝镜像
        warn "npm install 失败，尝试使用淘宝镜像..."
        retry "npm install --registry=https://registry.npmmirror.com --legacy-peer-deps" "npm install (镜像)" 3 20 || {
            error "前端依赖安装失败"
            return 1
        }
    }

    # 构建生产版本
    info "构建生产版本..."
    retry "npm run build" "npm run build" 2 10 || {
        error "前端构建失败"
        return 1
    }

    # 检查构建产物
    if [ ! -d "dist" ] || [ ! -f "dist/index.html" ]; then
        error "前端构建产物不存在"
        return 1
    fi

    # 复制构建产物
    mkdir -p /var/www/account-permission
    rm -rf /var/www/account-permission/*
    cp -r dist/* /var/www/account-permission/

    info "✅ 前端构建完成"
}

# 配置服务
setup_services() {
    step "配置服务..."

    # 检查后端目录
    if [ ! -f "${PROJECT_DIR}/backend/venv/bin/uvicorn" ]; then
        error "后端虚拟环境不存在，请先运行后端配置"
        return 1
    fi

    if [ "$HAS_SYSTEMD" = true ]; then
        # 使用 systemd
        setup_systemd_service
    else
        # 使用启动脚本
        setup_startup_script
    fi
}

# 配置 systemd 服务
setup_systemd_service() {
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
StandardOutput=journal
StandardError=journal

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
        warn "后端服务启动异常，查看日志: journalctl -u account-permission-backend -n 20"
    fi
}

# 配置启动脚本（无 systemd 时使用）
setup_startup_script() {
    # 创建启动脚本
    cat > ${PROJECT_DIR}/start.sh << 'EOF'
#!/bin/bash
# 服务启动脚本

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
            rm -f "$PID_FILE"
        else
            echo "后端服务未运行"
            rm -f "$PID_FILE"
        fi
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
    *)
        echo "用法: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac
EOF
    chmod +x ${PROJECT_DIR}/start.sh

    # 停止旧进程
    if [ -f "${PROJECT_DIR}/.backend.pid" ]; then
        local old_pid=$(cat "${PROJECT_DIR}/.backend.pid")
        kill "$old_pid" 2>/dev/null
        rm -f "${PROJECT_DIR}/.backend.pid"
    fi

    # 启动后端
    cd ${PROJECT_DIR}/backend
    source venv/bin/activate
    nohup uvicorn app.main:app --host 0.0.0.0 --port ${BACKEND_PORT} > ${PROJECT_DIR}/backend.log 2>&1 &
    echo $! > ${PROJECT_DIR}/.backend.pid
    deactivate

    sleep 3
    if kill -0 $(cat ${PROJECT_DIR}/.backend.pid) 2>/dev/null; then
        info "✅ 后端服务启动完成 (PID: $(cat ${PROJECT_DIR}/.backend.pid))"
    else
        warn "后端服务启动异常，查看日志: cat ${PROJECT_DIR}/backend.log"
    fi
}

# 配置 Nginx
setup_nginx() {
    step "配置 Nginx..."

    # 检查前端构建产物
    if [ ! -f "/var/www/account-permission/index.html" ]; then
        error "前端构建产物不存在，请先构建前端"
        return 1
    fi

    # 检查端口
    if ! check_port $FRONTEND_PORT; then
        warn "端口 ${FRONTEND_PORT} 被占用，尝试释放..."
        if [ -f /etc/nginx/sites-enabled/default ]; then
            rm -f /etc/nginx/sites-enabled/default
        fi
        stop_nginx 2>/dev/null
        sleep 1
    fi

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
后端: http://$(hostname -I | awk '{print $1}'):${BACKEND_PORT}/docs

常用命令
--------------------------------------------
EOF

    if [ "$HAS_SYSTEMD" = true ]; then
        cat >> ${PROJECT_DIR}/.credentials << EOF
查看后端状态: sudo systemctl status account-permission-backend
重启后端: sudo systemctl restart account-permission-backend
查看后端日志: sudo journalctl -u account-permission-backend -f
EOF
    else
        cat >> ${PROJECT_DIR}/.credentials << EOF
启动后端: ${PROJECT_DIR}/start.sh start
停止后端: ${PROJECT_DIR}/start.sh stop
重启后端: ${PROJECT_DIR}/start.sh restart
查看后端状态: ${PROJECT_DIR}/start.sh status
查看后端日志: cat ${PROJECT_DIR}/backend.log
EOF
    fi

    cat >> ${PROJECT_DIR}/.credentials << EOF
重启 Nginx: sudo nginx -s reload

============================================
EOF

    chmod 600 ${PROJECT_DIR}/.credentials

    info "凭证已保存到: ${PROJECT_DIR}/.credentials"
}

# 验证部署
verify_deployment() {
    step "验证部署..."

    local all_ok=true

    # 检查后端服务
    if [ "$HAS_SYSTEMD" = true ]; then
        if systemctl is-active --quiet account-permission-backend; then
            info "✅ 后端服务运行正常"
        else
            warn "⚠️  后端服务启动异常"
            all_ok=false
        fi
    else
        if [ -f "${PROJECT_DIR}/.backend.pid" ] && kill -0 $(cat "${PROJECT_DIR}/.backend.pid") 2>/dev/null; then
            info "✅ 后端服务运行正常"
        else
            warn "⚠️  后端服务启动异常"
            all_ok=false
        fi
    fi

    # 检查 Nginx
    if pgrep -x nginx > /dev/null; then
        info "✅ Nginx 运行正常"
    else
        warn "⚠️  Nginx 启动异常"
        all_ok=false
    fi

    # 测试 API
    sleep 2
    local api_code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:${BACKEND_PORT}/docs 2>/dev/null)
    if [ "$api_code" = "200" ]; then
        info "✅ 后端 API 可访问"
    else
        warn "⚠️  后端 API 访问异常 (HTTP: $api_code)"
        all_ok=false
    fi

    # 测试前端
    local front_code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:${FRONTEND_PORT}/ 2>/dev/null)
    if [ "$front_code" = "200" ]; then
        info "✅ 前端页面可访问"
    else
        warn "⚠️  前端页面访问异常 (HTTP: $front_code)"
        all_ok=false
    fi

    # 测试登录
    local login_result=$(curl -s http://localhost:${FRONTEND_PORT}/api/auth/login \
        -X POST -H "Content-Type: application/json" \
        -d '{"username":"admin","password":"admin123"}' 2>/dev/null)
    if echo "$login_result" | grep -q '"code":200'; then
        info "✅ 登录功能正常"
    else
        warn "⚠️  登录测试失败"
        all_ok=false
    fi

    if [ "$all_ok" = true ]; then
        echo ""
        info "🎉 所有服务验证通过！"
    else
        echo ""
        warn "⚠️  部分服务异常，请根据上述提示排查问题"
    fi
}

# 显示部署信息
show_info() {
    local IP=$(hostname -I | awk '{print $1}')

    echo ""
    echo "============================================"
    echo "  部署完成！"
    echo "============================================"
    echo ""
    echo "  访问地址:"
    echo "    前端: http://${IP}:${FRONTEND_PORT}"
    echo "    后端: http://${IP}:${BACKEND_PORT}/docs"
    echo ""
    echo "  默认管理员账号:"
    echo "    用户名: admin"
    echo "    密码: admin123"
    echo ""
    echo "  首次登录请立即修改密码！"
    echo ""
    echo "  凭证文件: ${PROJECT_DIR}/.credentials"
    echo ""

    if [ "$HAS_SYSTEMD" = false ]; then
        echo "  服务管理命令:"
        echo "    启动: ${PROJECT_DIR}/start.sh start"
        echo "    停止: ${PROJECT_DIR}/start.sh stop"
        echo "    重启: ${PROJECT_DIR}/start.sh restart"
        echo "    状态: ${PROJECT_DIR}/start.sh status"
        echo ""
    fi

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

    # 安装阶段（允许部分失败后继续）
    install_dependencies || warn "系统依赖安装有问题，继续..."
    install_python || { error "Python 安装失败，无法继续"; exit 1; }
    install_nodejs || warn "Node.js 安装有问题，前端构建可能失败"
    install_mysql || { error "数据库安装失败，无法继续"; exit 1; }
    install_nginx || warn "Nginx 安装有问题，继续..."

    # 配置阶段
    setup_mysql || { error "数据库配置失败，无法继续"; exit 1; }
    deploy_project || { error "项目部署失败，无法继续"; exit 1; }
    setup_backend || { error "后端配置失败，无法继续"; exit 1; }

    # 前端构建（非关键，允许失败）
    if build_frontend; then
        info "前端构建成功"
    else
        warn "前端构建失败，可以稍后手动构建"
        warn "cd ${PROJECT_DIR}/frontend && npm install && npm run build"
    fi

    # 服务配置
    setup_services || warn "服务配置有问题"
    setup_nginx || warn "Nginx 配置有问题"

    # 保存凭证
    save_credentials

    # 验证
    verify_deployment

    # 显示信息
    show_info
}

# 运行主流程
main "$@"
