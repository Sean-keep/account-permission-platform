# 人员账号与权限台账管理平台

<p align="center">
  <img src="https://img.shields.io/badge/Vue-3.x-blue" alt="Vue 3">
  <img src="https://img.shields.io/badge/FastAPI-0.100+-green" alt="FastAPI">
  <img src="https://img.shields.io/badge/MySQL-8.0-orange" alt="MySQL 8">
  <img src="https://img.shields.io/badge/Docker-Compose-blue" alt="Docker">
  <img src="https://img.shields.io/badge/License-MIT-yellow" alt="License">
</p>

企业级人员账号与权限台账管理平台，专注于人员、系统、账号和权限的统一管理，支持离职人员账号自动回收。

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

## 🚀 快速部署

### Ubuntu 一键部署

```bash
# 克隆项目
git clone https://github.com/Sean-keep/account-permission-platform.git
cd account-permission-platform

# 执行部署脚本
chmod +x deploy.sh
sudo ./deploy.sh
```

部署完成后访问：
- 前端地址: `http://你的服务器IP:3000`
- 默认账号: `admin / admin123`

### Docker Compose 部署

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

## 🛠️ 开发环境

### 前端开发

```bash
cd frontend
npm install
npm run dev
```

访问 http://localhost:5173

### 后端开发

```bash
cd backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# 创建环境配置
cat > .env << EOF
MYSQL_HOST=localhost
MYSQL_PORT=3307
MYSQL_USER=app_user
MYSQL_PASSWORD=your_password
MYSQL_DATABASE=account_permission
JWT_SECRET_KEY=your-secret-key
JWT_EXPIRE_MINUTES=480
EOF

# 启动服务
uvicorn app.main:app --reload --port 9000
```

访问 http://localhost:9000/docs 查看 API 文档

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
├── docker-compose.yml           # Docker 编排
├── deploy.sh                    # Ubuntu 部署脚本
└── README.md
```

## 📡 API 接口

| 模块 | 接口 | 说明 |
|------|------|------|
| 认证 | `POST /api/auth/login` | 用户登录 |
| 认证 | `POST /api/auth/change-password` | 修改密码 |
| 人员 | `GET /api/personnel` | 人员列表 |
| 人员 | `POST /api/personnel` | 创建人员 |
| 人员 | `POST /api/personnel/{id}/resign` | 离职处理 |
| 系统 | `GET /api/systems` | 系统列表 |
| 系统 | `POST /api/systems` | 创建系统 |
| 账号 | `GET /api/accounts` | 账号列表 |
| 账号 | `POST /api/accounts` | 创建账号 |
| 关系 | `POST /api/relations/bind-account` | 绑定人员账号 |
| 关系 | `POST /api/relations/unbind-account` | 解绑人员账号 |
| 统计 | `GET /api/dashboard/stats` | 工作台统计 |

## ⚙️ 环境变量

| 变量名 | 说明 | 默认值 |
|--------|------|--------|
| `MYSQL_HOST` | MySQL 主机 | mysql |
| `MYSQL_PORT` | MySQL 端口 | 3306 |
| `MYSQL_USER` | MySQL 用户名 | app_user |
| `MYSQL_PASSWORD` | MySQL 密码 | - |
| `MYSQL_DATABASE` | 数据库名 | account_permission |
| `JWT_SECRET_KEY` | JWT 密钥 | - |
| `JWT_EXPIRE_MINUTES` | Token 过期时间(分钟) | 480 |

## 📊 数据备份

```bash
# 备份数据库
docker exec account-permission-platform-mysql-1 mysqldump -u app_user -p account_permission > backup_$(date +%Y%m%d).sql

# 恢复数据库
docker exec -i account-permission-platform-mysql-1 mysql -u app_user -p account_permission < backup.sql
```

## 🔧 常用命令

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

## ❓ 常见问题

### Q: 忘记管理员密码怎么办？

```bash
# 进入后端容器
docker exec -it account-permission-platform-backend-1 bash

# 运行密码重置脚本
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

编辑 `docker-compose.yml` 文件，修改端口映射：

```yaml
services:
  frontend:
    ports:
      - "8080:80"  # 改为你想要的端口
  backend:
    ports:
      - "9001:9000"  # 改为你想要的端口
```

### Q: 如何查看数据库？

```bash
# 进入 MySQL 容器
docker exec -it account-permission-platform-mysql-1 mysql -u app_user -p account_permission

# 查看表
SHOW TABLES;

# 查看人员
SELECT * FROM personnel;
```

## 📄 许可证

[MIT License](LICENSE)

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📧 联系方式

如有问题，请提交 Issue 或联系维护者。
