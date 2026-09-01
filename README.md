# 人员账号与权限台账管理平台

一个用于管理企业人员、系统、账号和权限的综合性台账管理平台。主要用于跟踪人员账号绑定关系，支持离职人员账号自动回收。

## 功能特性

### 核心功能
- **人员管理** - 员工信息录入、编辑、离职处理
- **系统管理** - 业务系统登记和管理
- **账号管理** - 系统账号创建和维护
- **审计日志** - 所有操作记录可追溯

### 台账功能
- **人员台账** - 查看人员关联的所有账号
- **系统台账** - 查看系统关联的所有人员和账号

### 关系管理
- 人员 ↔ 账号绑定（支持主要/次要/临时类型）
- 离职处理自动解绑账号并撤销权限
- 删除人员/账号自动清理绑定关系

### 工作台
- 统计概览（人员、系统、账号、绑定数量）
- 部门人员分布
- 最近操作记录

## 技术栈

### 前端
- Vue 3 + TypeScript
- Vite 构建工具
- Element Plus UI 组件库
- Vue Router 路由管理
- Axios HTTP 客户端

### 后端
- Python 3.12
- FastAPI Web框架
- SQLAlchemy ORM
- JWT 认证
- bcrypt 密码加密

### 数据库
- MySQL 8.0

### 部署
- Docker Compose 容器化部署

## 快速开始

### 环境要求
- Docker 20+
- Docker Compose 2+

### 部署步骤

1. 克隆项目
```bash
git clone <repository-url>
cd account-permission-platform
```

2. 启动服务
```bash
docker-compose up -d
```

3. 访问系统
- 前端地址: http://localhost:3000
- 后端API: http://localhost:9000
- 默认账号: admin / admin123 (首次登录后请修改密码)

### 开发环境

**前端开发**
```bash
cd frontend
npm install
npm run dev
```

**后端开发**
```bash
cd backend
python -m venv venv
source venv/bin/activate  # Linux/Mac
pip install -r requirements.txt
uvicorn app.main:app --reload --port 9000
```

## 项目结构

```
account-permission-platform/
├── frontend/                    # 前端项目
│   ├── src/
│   │   ├── api/                # API 接口
│   │   ├── components/         # 公共组件
│   │   ├── router/             # 路由配置
│   │   ├── views/              # 页面视图
│   │   │   ├── Dashboard/      # 工作台
│   │   │   ├── Personnel/      # 人员管理
│   │   │   ├── Systems/        # 系统管理
│   │   │   ├── Accounts/       # 账号管理
│   │   │   ├── PersonnelAccounts/  # 人员台账
│   │   │   ├── SystemPersonnel/    # 系统台账
│   │   │   └── AuditLogs/      # 审计日志
│   │   └── main.ts
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
└── README.md
```

## API 接口

### 认证相关
- `POST /api/auth/login` - 用户登录
- `POST /api/auth/change-password` - 修改密码
- `GET /api/auth/me` - 获取当前用户

### 人员管理
- `GET /api/personnel` - 人员列表
- `POST /api/personnel` - 创建人员
- `PUT /api/personnel/{id}` - 更新人员
- `DELETE /api/personnel/{id}` - 删除人员
- `POST /api/personnel/{id}/resign` - 离职处理

### 系统管理
- `GET /api/systems` - 系统列表
- `POST /api/systems` - 创建系统
- `PUT /api/systems/{id}` - 更新系统
- `DELETE /api/systems/{id}` - 删除系统

### 账号管理
- `GET /api/accounts` - 账号列表
- `POST /api/accounts` - 创建账号
- `PUT /api/accounts/{id}` - 更新账号
- `DELETE /api/accounts/{id}` - 删除账号

### 关系管理
- `POST /api/relations/bind-account` - 绑定人员账号
- `POST /api/relations/unbind-account` - 解绑人员账号

### 统计查询
- `GET /api/dashboard/stats` - 工作台统计
- `GET /api/dashboard/departments` - 部门列表

## 配置说明

### 环境变量

**后端配置 (backend/.env)**
```env
MYSQL_HOST=localhost
MYSQL_PORT=3307
MYSQL_USER=your_username
MYSQL_PASSWORD=your_password
MYSQL_DATABASE=account_permission
JWT_SECRET_KEY=your-secret-key
JWT_EXPIRE_MINUTES=480
```

**Docker Compose 配置**
- 前端端口: 3000
- 后端端口: 9000
- MySQL端口: 3307

## 使用说明

### 1. 人员管理
- 录入员工信息（姓名、工号、部门、职位等）
- 支持按部门、状态筛选
- 离职处理自动解绑关联账号

### 2. 系统管理
- 登记业务系统信息
- 支持按名称搜索
- 查看系统关联人员

### 3. 账号管理
- 创建系统账号
- 绑定到具体人员
- 支持多种账号类型（普通/管理员/服务/共享）

### 4. 台账查询
- **人员台账**: 选择人员查看其所有关联账号
- **系统台账**: 选择系统查看其所有关联人员和账号

### 5. 工作台
- 查看整体统计数据
- 部门人员分布
- 最近操作记录

## 数据备份

### 备份数据库
```bash
docker exec security-dashboard-v2 mysqldump -u your_username -p account_permission > backup.sql
```

### 恢复数据库
```bash
docker exec -i security-dashboard-v2 mysql -u your_username -p account_permission < backup.sql
```

## 常见问题

### Q: 忘记密码怎么办？
A: 目前只能通过数据库直接修改密码哈希值，或重新初始化数据库。

### Q: 如何批量导入人员？
A: 目前暂不支持批量导入，需要通过界面逐条录入。

### Q: 离职处理后能恢复吗？
A: 离职处理会自动解绑账号，解绑后需要手动重新绑定。

## 更新日志

### v1.0.0 (2026-09-01)
- 初始版本发布
- 人员、系统、账号管理
- 人员台账、系统台账
- 离职自动处理
- 工作台统计

## 许可证

MIT License
