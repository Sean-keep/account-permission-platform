# 人员账号与权限台账管理平台

<p align="center">
  <img src="https://img.shields.io/badge/Vue-3.x-blue" alt="Vue 3">
  <img src="https://img.shields.io/badge/FastAPI-0.100+-green" alt="FastAPI">
  <img src="https://img.shields.io/badge/MySQL-8.0-orange" alt="MySQL 8">
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
- 支持按名称搜索

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
| 前端 | Vue 3 + TypeScript + Element Plus + ECharts |
| 后端 | FastAPI + SQLAlchemy + Pydantic |
| 数据库 | MySQL 8.0 |
| 认证 | JWT + bcrypt |
| 部署 | Nginx + systemd |

---

## 🚀 部署方式

### 方式一：Ubuntu 一键脚本部署（推荐）

适用于全新 Ubuntu 服务器，自动完成环境安装、数据库配置、服务部署。

#### 环境要求

| 组件 | 版本要求 |
|------|----------|
| 操作系统 | Ubuntu 20.04 / 22.04 / 24.04 |
| Python | ≥ 3.10（脚本自动安装） |
| Node.js | ≥ 18（脚本自动安装） |
| MySQL | ≥ 8.0（脚本自动安装） |
| Nginx | 脚本自动安装 |

#### 部署步骤

```bash
# 1. 克隆项目
git clone https://github.com/Sean-keep/account-permission-platform.git
cd account-permission-platform

# 2. 执行部署脚本
chmod +x deploy-ubuntu.sh
sudo ./deploy-ubuntu.sh
```

部署脚本将自动完成：
1. 安装 Python 3、Node.js 18、MySQL 8.0、Nginx
2. 创建数据库和用户
3. 构建前端项目
4. 配置 Python 虚拟环境并安装依赖
5. 初始化数据库表
6. 创建 systemd 服务（前端构建、后端 API）
7. 配置 Nginx 反向代理
8. 启动所有服务

部署完成后访问：
- 前端地址: `http://你的服务器IP`
- 后端 API: `http://你的服务器IP/api`
- 默认账号: `admin / admin123`

---

### 方式二：Ubuntu 手动部署

适用于需要自定义配置或已有环境的服务器。

#### 2.1 环境要求

| 组件 | 版本要求 |
|------|----------|
| Python | ≥ 3.10 |
| Node.js | ≥ 18 |
| MySQL | ≥ 8.0 |
| Nginx | ≥ 1.18 |

#### 2.2 安装系统依赖

```bash
# 更新系统
sudo apt update && sudo apt upgrade -y

# 安装 Python 3 和 pip
sudo apt install -y python3 python3-pip python3-venv python3-dev

# 安装 Node.js 18（如未安装）
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs

# 安装 MySQL 8.0
sudo apt install -y mysql-server mysql-client

# 安装 Nginx
sudo apt install -y nginx

# 安装构建工具
sudo apt install -y build-essential libssl-dev libffi-dev
```

#### 2.3 配置 MySQL

```bash
# 启动 MySQL
sudo systemctl start mysql
sudo systemctl enable mysql

# 安全初始化（设置 root 密码等）
sudo mysql_secure_installation

# 创建数据库和用户
sudo mysql -u root -p << EOF
CREATE DATABASE account_permission DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'app_user'@'localhost' IDENTIFIED BY 'your_password';
GRANT ALL PRIVILEGES ON account_permission.* TO 'app_user'@'localhost';
FLUSH PRIVILEGES;
EOF
```

#### 2.4 部署后端

```bash
# 进入后端目录
cd /path/to/account-permission-platform/backend

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

# 初始化数据库表
python3 -c "
from app.models.base import Base, engine
from app.models import user, personnel, system, account, audit_log
Base.metadata.create_all(bind=engine)
print('数据库表初始化完成')
"

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

#### 2.5 部署前端

```bash
# 进入前端目录
cd /path/to/account-permission-platform/frontend

# 安装依赖
npm install

# 构建生产版本
npm run build

# 复制构建产物到 Nginx 目录
sudo mkdir -p /var/www/account-permission
sudo cp -r dist/* /var/www/account-permission/

# 配置 Nginx
sudo tee /etc/nginx/sites-available/account-permission << EOF
server {
    listen 80;
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

# 启用站点
sudo ln -sf /etc/nginx/sites-available/account-permission /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

# 测试并重启 Nginx
sudo nginx -t && sudo systemctl restart nginx
```

#### 2.6 验证部署

```bash
# 检查后端服务状态
sudo systemctl status account-permission-backend

# 检查 Nginx 状态
sudo systemctl status nginx

# 测试 API
curl http://localhost:9000/api/auth/login -X POST -H "Content-Type: application/json" -d '{"username":"admin","password":"admin123"}'

# 测试前端
curl -I http://localhost/
```

---

### 方式三：Docker Compose 部署

适用于快速体验或开发环境。

```bash
# 克隆项目
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

# 启动服务
docker compose up -d --build

# 查看状态
docker compose ps
```

部署完成后访问：
- 前端地址: `http://localhost:3000`
- 后端 API: `http://localhost:9000`
- 默认账号: `admin / admin123`

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
│   ├── nginx.conf              # Nginx 配置参考
│   └── package.json
├── backend/                     # 后端项目
│   ├── app/
│   │   ├── api/                # API 路由
│   │   ├── core/               # 核心配置
│   │   ├── models/             # 数据模型
│   │   ├── schemas/            # 数据验证
│   │   └── services/           # 业务服务
│   ├── requirements.txt
│   └── Dockerfile
├── deploy.sh                    # Docker 部署脚本
├── deploy-ubuntu.sh             # Ubuntu 一键部署脚本（无 Docker）
├── docker-compose.yml           # Docker 编排
└── README.md
```

---

## 📡 API 接口

| 模块 | 接口 | 方法 | 说明 |
|------|------|------|------|
| 认证 | `/api/auth/login` | POST | 用户登录 |
| 认证 | `/api/auth/change-password` | POST | 修改密码 |
| 人员 | `/api/personnel` | GET | 人员列表 |
| 人员 | `/api/personnel` | POST | 创建人员 |
| 人员 | `/api/personnel/{id}` | PUT | 更新人员 |
| 人员 | `/api/personnel/{id}` | DELETE | 删除人员 |
| 人员 | `/api/personnel/{id}/resign` | POST | 离职处理 |
| 系统 | `/api/systems` | GET | 系统列表 |
| 系统 | `/api/systems` | POST | 创建系统 |
| 系统 | `/api/systems/{id}` | PUT | 更新系统 |
| 账号 | `/api/accounts` | GET | 账号列表 |
| 账号 | `/api/accounts` | POST | 创建账号 |
| 账号 | `/api/accounts/{id}` | PUT | 更新账号 |
| 关系 | `/api/relations/bind-account` | POST | 绑定人员账号 |
| 关系 | `/api/relations/unbind-account` | POST | 解绑人员账号 |
| 台账 | `/api/ledgers/personnel/{id}` | GET | 人员台账 |
| 台账 | `/api/ledgers/system/{id}` | GET | 系统台账 |
| 统计 | `/api/dashboard/stats` | GET | 工作台统计 |
| 审计 | `/api/audit-logs` | GET | 审计日志 |

启动后访问 API 文档：`http://localhost:9000/docs`

---

## ⚙️ 环境变量

| 变量名 | 说明 | 默认值 |
|--------|------|--------|
| `MYSQL_HOST` | MySQL 主机 | `localhost` |
| `MYSQL_PORT` | MySQL 端口 | `3306` |
| `MYSQL_USER` | MySQL 用户名 | `app_user` |
| `MYSQL_PASSWORD` | MySQL 密码 | - |
| `MYSQL_DATABASE` | 数据库名 | `account_permission` |
| `JWT_SECRET_KEY` | JWT 密钥（至少 32 字符） | - |
| `JWT_EXPIRE_MINUTES` | Token 过期时间（分钟） | `480` |

---

## 📊 数据备份

### MySQL 手动备份

```bash
# 备份数据库
mysqldump -u app_user -p account_permission > backup_$(date +%Y%m%d).sql

# 恢复数据库
mysql -u app_user -p account_permission < backup.sql
```

### 自动备份（crontab）

```bash
# 编辑 crontab
crontab -e

# 添加每日凌晨 2 点备份
0 2 * * * mysqldump -u app_user -p'your_password' account_permission > /backup/account_permission_$(date +\%Y\%m\%d).sql
```

---

## 🔧 常用命令

### 服务管理

```bash
# 查看后端服务状态
sudo systemctl status account-permission-backend

# 重启后端服务
sudo systemctl restart account-permission-backend

# 查看后端日志
sudo journalctl -u account-permission-backend -f

# 重启 Nginx
sudo systemctl restart nginx

# 查看 Nginx 日志
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log
```

### Docker 方式

```bash
# 查看服务状态
docker compose ps

# 查看日志
docker compose logs -f

# 重启服务
docker compose restart

# 停止服务
docker compose down

# 更新并重启
git pull
docker compose up -d --build
```

---

## ❓ 常见问题

### Q: 忘记管理员密码怎么办？

**Ubuntu 手动部署方式：**

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

**Docker 方式：**

```bash
docker exec -it account-permission-platform-backend-1 bash
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

### Q: 如何修改端口？

**Ubuntu 手动部署方式：**

1. 修改后端端口：编辑 `/etc/systemd/system/account-permission-backend.service` 中的 `--port` 参数
2. 修改前端端口：编辑 `/etc/nginx/sites-available/account-permission` 中的 `listen` 参数
3. 重启服务：`sudo systemctl daemon-reload && sudo systemctl restart account-permission-backend && sudo systemctl restart nginx`

### Q: 如何查看数据库？

```bash
# 登录 MySQL
mysql -u app_user -p account_permission

# 查看表
SHOW TABLES;

# 查看人员
SELECT * FROM personnel;

# 查看账号
SELECT * FROM accounts;
```

### Q: 后端服务启动失败怎么办？

```bash
# 查看详细错误日志
sudo journalctl -u account-permission-backend -n 50

# 手动启动测试
cd /opt/account-permission-platform/backend
source venv/bin/activate
uvicorn app.main:app --host 0.0.0.0 --port 9000
```

### Q: 前端页面空白怎么办？

1. 检查 Nginx 配置是否正确：`sudo nginx -t`
2. 检查构建产物是否存在：`ls -la /var/www/account-permission/`
3. 检查 Nginx 错误日志：`sudo tail -f /var/log/nginx/error.log`
4. 确认后端 API 可访问：`curl http://localhost:9000/api/auth/login -X POST -H "Content-Type: application/json" -d '{"username":"admin","password":"admin123"}'`

---

## 📄 许可证

[MIT License](LICENSE)

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📧 联系方式

如有问题，请提交 Issue 或联系维护者。
