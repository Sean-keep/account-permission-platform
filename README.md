# 人员账号与权限台账管理平台

<p align="center">
  <img src="https://img.shields.io/badge/Vue-3.x-blue" alt="Vue 3">
  <img src="https://img.shields.io/badge/FastAPI-0.100+-green" alt="FastAPI">
  <img src="https://img.shields.io/badge/MySQL-8.0-orange" alt="MySQL 8">
  <img src="https://img.shields.io/badge/Node.js-22+-brightgreen" alt="Node.js">
  <img src="https://img.shields.io/badge/License-MIT-yellow" alt="License">
</p>

企业级人员账号与权限台账管理平台，专注于人员、系统、账号和权限的统一管理，支持离职人员账号自动回收。

---

## ✨ 功能特性

### 📊 工作台
- 统计概览（人员、系统、账号、绑定数量）
- 部门人员分布图表
- 最近操作记录

### 👥 人员管理
- 员工信息录入、编辑、删除
- 离职处理（自动解绑账号、撤销权限）
- 按部门、状态筛选

### 🖥️ 系统管理
- 业务系统登记和维护
- 查看系统关联人员

### 🔑 账号管理
- 系统账号创建和维护
- 绑定/解绑人员
- 支持多种账号类型（普通/管理员/服务/共享）

### 📋 台账查询
- **人员台账** - 查看人员关联的所有账号
- **系统台账** - 查看系统关联的所有人员和账号

### 📝 审计日志
- 所有操作记录可追溯
- 支持按操作类型、对象类型筛选

---

## 🛠️ 技术栈

| 层级 | 技术 |
|------|------|
| 前端 | Vue 3 + TypeScript + Element Plus + Vite 8 |
| 后端 | FastAPI + SQLAlchemy + Pydantic |
| 数据库 | MySQL 8.0 / MariaDB |
| 认证 | JWT + bcrypt |
| 部署 | Nginx + systemd（或直接进程管理） |

### 环境要求

| 组件 | 版本要求 |
|------|----------|
| Python | >= 3.10 |
| Node.js | >= 22 |
| MySQL | >= 8.0（或 MariaDB >= 10.5） |
| Nginx | >= 1.18 |

---

## 🚀 快速部署

### 方式一：Ubuntu 一键脚本部署（推荐）

#### 环境准备

确保服务器可以访问外网，然后执行：

```bash
# 克隆项目
git clone https://github.com/Sean-keep/account-permission-platform.git
cd account-permission-platform

# 执行部署脚本
chmod +x deploy-ubuntu.sh
sudo ./deploy-ubuntu.sh
```

#### 脚本功能

部署脚本会自动完成以下操作：

1. ✅ 安装 Python 3、Node.js 22、Nginx
2. ✅ 安装 MySQL（或使用外部数据库）
3. ✅ 创建数据库和用户
4. ✅ 构建前端项目
5. ✅ 配置 Python 虚拟环境
6. ✅ 启动后端服务
7. ✅ 配置 Nginx 反向代理

#### 使用外部数据库

如果需要使用外部数据库，在运行脚本前先创建配置文件：

```bash
# 创建 .env 文件
cat > backend/.env << 'EOF'
MYSQL_HOST=你的数据库IP
MYSQL_PORT=3306
MYSQL_USER=你的数据库用户
MYSQL_PASSWORD=你的数据库密码
MYSQL_DATABASE=account_permission
JWT_SECRET_KEY=你的JWT密钥至少32位
JWT_EXPIRE_MINUTES=480
EOF
```

然后在外部数据库执行初始化：

```sql
CREATE DATABASE account_permission DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER '你的用户'@'%' IDENTIFIED BY '你的密码';
GRANT ALL PRIVILEGES ON account_permission.* TO '你的用户'@'%';
FLUSH PRIVILEGES;
```

再运行部署脚本：

```bash
sudo ./deploy-ubuntu.sh
```

脚本会自动检测 `.env` 配置，跳过 MySQL 安装。

#### 部署完成

部署完成后访问：
- 前端地址: `http://你的服务器IP`
- 默认账号: `admin / admin123`

---

### 方式二：手动部署

#### 2.1 安装系统依赖

```bash
# Ubuntu 22.04/24.04
sudo apt update
sudo apt install -y python3 python3-pip python3-venv python3-dev
sudo apt install -y nginx

# 安装 Node.js 22
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs

# 安装 MySQL
sudo apt install -y mysql-server mysql-client
```

#### 2.2 配置 MySQL

```bash
# 启动 MySQL
sudo systemctl start mysql
sudo systemctl enable mysql

# 创建数据库和用户
sudo mysql -u root << EOF
CREATE DATABASE account_permission DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'app_user'@'localhost' IDENTIFIED BY 'your_password';
GRANT ALL PRIVILEGES ON account_permission.* TO 'app_user'@'localhost';
FLUSH PRIVILEGES;
EOF
```

#### 2.3 部署后端

```bash
# 复制项目到目标目录
sudo mkdir -p /opt/account-permission-platform
sudo cp -r backend /opt/account-permission-platform/
sudo cp -r frontend /opt/account-permission-platform/

# 进入后端目录
cd /opt/account-permission-platform/backend

# 创建虚拟环境
python3 -m venv venv
source venv/bin/activate

# 安装依赖
pip install -r requirements.txt

# 创建环境配置
cat > .env << EOF
MYSQL_HOST=localhost
MYSQL_PORT=3306
MYSQL_USER=app_user
MYSQL_PASSWORD=your_password
MYSQL_DATABASE=account_permission
JWT_SECRET_KEY=$(openssl rand -base64 32)
JWT_EXPIRE_MINUTES=480
EOF

# 创建 systemd 服务
sudo tee /etc/systemd/system/account-permission-backend.service << EOF
[Unit]
Description=Account Permission Platform Backend
After=network.target mysql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/account-permission-platform/backend
EnvironmentFile=/opt/account-permission-platform/backend/.env
ExecStart=/opt/account-permission-platform/backend/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 9000
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 启动服务
sudo systemctl daemon-reload
sudo systemctl enable account-permission-backend
sudo systemctl start account-permission-backend
```

#### 2.4 部署前端

```bash
cd /opt/account-permission-platform/frontend

# 安装依赖
npm install --legacy-peer-deps

# 构建
npm run build

# 复制到 Nginx 目录
sudo mkdir -p /var/www/account-permission
sudo cp -r dist/* /var/www/account-permission/
```

#### 2.5 配置 Nginx

```bash
sudo tee /etc/nginx/sites-available/account-permission << EOF
server {
    listen 80;
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
        proxy_pass http://127.0.0.1:9000/api/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Content-Type \$content_type;
        proxy_set_header Content-Length \$content_length;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/account-permission /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl restart nginx
```

#### 2.6 验证部署

```bash
# 检查后端
curl http://localhost:9000/api/health

# 测试登录
curl http://localhost/api/auth/login -X POST -H "Content-Type: application/json" -d '{"username":"admin","password":"admin123"}'
```

---

### 方式三：Docker Compose 部署

```bash
git clone https://github.com/Sean-keep/account-permission-platform.git
cd account-permission-platform

# 创建环境配置
cat > backend/.env << EOF
MYSQL_HOST=mysql
MYSQL_PORT=3306
MYSQL_USER=app_user
MYSQL_PASSWORD=your_password
MYSQL_DATABASE=account_permission
JWT_SECRET_KEY=$(openssl rand -base64 32)
JWT_EXPIRE_MINUTES=480
EOF

# 启动
docker compose up -d --build
```

---

## 📁 项目结构

```
account-permission-platform/
├── frontend/                    # 前端项目
│   ├── src/
│   │   ├── api/                # API 接口
│   │   ├── components/         # 公共组件
│   │   ├── router/             # 路由配置
│   │   └── views/              # 页面视图
│   │       ├── Dashboard/      # 工作台
│   │       ├── Personnel/      # 人员管理
│   │       ├── Systems/        # 系统管理
│   │       ├── Accounts/       # 账号管理
│   │       ├── PersonnelAccounts/  # 人员台账
│   │       ├── SystemPersonnel/    # 系统台账
│   │       └── AuditLogs/      # 审计日志
│   └── package.json
├── backend/                     # 后端项目
│   ├── app/
│   │   ├── api/                # API 路由
│   │   ├── core/               # 核心配置
│   │   ├── models/             # 数据模型
│   │   ├── schemas/            # 数据验证
│   │   └── services/           # 业务服务
│   └── requirements.txt
├── deploy-ubuntu.sh             # Ubuntu 一键部署脚本
├── docker-compose.yml           # Docker 编排
└── README.md
```

---

## 📡 API 接口

| 模块 | 接口 | 方法 | 说明 |
|------|------|------|------|
| 认证 | `/api/auth/login` | POST | 用户登录 |
| 认证 | `/api/auth/change-password` | POST | 修改密码 |
| 人员 | `/api/personnel` | GET/POST | 人员列表/创建 |
| 人员 | `/api/personnel/{id}` | PUT/DELETE | 更新/删除 |
| 人员 | `/api/personnel/{id}/resign` | POST | 离职处理 |
| 系统 | `/api/systems` | GET/POST | 系统列表/创建 |
| 账号 | `/api/accounts` | GET/POST | 账号列表/创建 |
| 关系 | `/api/relations/bind-account` | POST | 绑定人员账号 |
| 关系 | `/api/relations/unbind-account` | POST | 解绑人员账号 |
| 台账 | `/api/ledgers/personnel/{id}` | GET | 人员台账 |
| 台账 | `/api/ledgers/system/{id}` | GET | 系统台账 |
| 统计 | `/api/dashboard/stats` | GET | 工作台统计 |
| 审计 | `/api/audit-logs` | GET | 审计日志 |

API 文档：`http://your-server:9000/docs`

---

## ⚙️ 环境变量

在 `backend/.env` 中配置：

| 变量名 | 说明 | 示例 |
|--------|------|------|
| `MYSQL_HOST` | MySQL 主机 | `localhost` 或 `192.168.1.100` |
| `MYSQL_PORT` | MySQL 端口 | `3306` |
| `MYSQL_USER` | MySQL 用户名 | `app_user` |
| `MYSQL_PASSWORD` | MySQL 密码 | `your_password` |
| `MYSQL_DATABASE` | 数据库名 | `account_permission` |
| `JWT_SECRET_KEY` | JWT 密钥（至少 32 字符） | 随机生成 |
| `JWT_EXPIRE_MINUTES` | Token 过期时间 | `480` |

---

## 🔧 服务管理

### systemd 方式

```bash
# 查看状态
sudo systemctl status account-permission-backend

# 启动/停止/重启
sudo systemctl start account-permission-backend
sudo systemctl stop account-permission-backend
sudo systemctl restart account-permission-backend

# 查看日志
sudo journalctl -u account-permission-backend -f
```

### 脚本方式（无 systemd 环境）

```bash
# 启动
/opt/account-permission-platform/start.sh start

# 停止
/opt/account-permission-platform/start.sh stop

# 重启
/opt/account-permission-platform/start.sh restart

# 状态
/opt/account-permission-platform/start.sh status

# 查看日志
tail -f /opt/account-permission-platform/backend.log
```

---

## ❓ 常见问题

### Q: 忘记管理员密码怎么办？

```bash
cd /opt/account-permission-platform/backend
source venv/bin/activate

python3 -c "
from app.core.security import get_password_hash
from app.models.base import SessionLocal
from app.models.user import User

db = SessionLocal()
user = db.query(User).filter(User.username == 'admin').first()
if user:
    user.password_hash = get_password_hash('admin123')
    db.commit()
    print('密码已重置为: admin123')
db.close()
"
```

### Q: 如何使用外部数据库？

1. 创建 `backend/.env` 文件配置数据库连接
2. 在外部数据库创建库和用户
3. 运行部署脚本，会自动跳过 MySQL 安装

### Q: Node.js 版本过低怎么办？

```bash
# 安装 Node.js 22
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs

# 或使用 nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
source ~/.bashrc
nvm install 22
```

### Q: 前端构建失败怎么办？

```bash
cd /opt/account-permission-platform/frontend

# 清理后重新构建
rm -rf node_modules dist
npm install --legacy-peer-deps
npm run build
```

### Q: 后端启动失败怎么办？

```bash
# 查看日志
cat /opt/account-permission-platform/backend.log

# 或 systemd 方式
sudo journalctl -u account-permission-backend -n 50

# 手动测试启动
cd /opt/account-permission-platform/backend
source venv/bin/activate
uvicorn app.main:app --host 0.0.0.0 --port 9000
```

---

## 📄 许可证

[MIT License](LICENSE)

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！
