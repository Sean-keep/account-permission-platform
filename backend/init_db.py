#!/usr/bin/env python3
"""
数据库初始化脚本
用于手动初始化数据库表和默认管理员账号

使用方法:
    cd /opt/account-permission-platform/backend
    source venv/bin/activate
    python init_db.py
"""

import sys
import os

# 确保能导入 app 模块
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from app.core.config import settings


def main():
    print("=" * 50)
    print("数据库初始化")
    print("=" * 50)
    print()

    # 显示数据库连接信息
    print(f"数据库主机: {settings.MYSQL_HOST}")
    print(f"数据库端口: {settings.MYSQL_PORT}")
    print(f"数据库用户: {settings.MYSQL_USER}")
    print(f"数据库名称: {settings.MYSQL_DATABASE}")
    print()

    # 测试数据库连接
    print("测试数据库连接...")
    from app.models.base import engine
    from sqlalchemy import text

    try:
        with engine.connect() as conn:
            result = conn.execute(text("SELECT 1"))
            print("✅ 数据库连接成功")
    except Exception as e:
        print(f"❌ 数据库连接失败: {e}")
        print()
        print("请检查 .env 配置文件:")
        print(f"  文件位置: {os.path.join(os.path.dirname(__file__), '.env')}")
        print()
        print("配置示例:")
        print("  MYSQL_HOST=你的数据库IP")
        print("  MYSQL_PORT=3306")
        print("  MYSQL_USER=你的数据库用户")
        print("  MYSQL_PASSWORD=你的数据库密码")
        print("  MYSQL_DATABASE=account_permission")
        print("  JWT_SECRET_KEY=你的JWT密钥至少32位")
        print("  JWT_EXPIRE_MINUTES=480")
        sys.exit(1)

    # 导入所有模型
    print()
    print("导入数据模型...")
    from app.models.base import Base
    from app.models import user, personnel, system, account, audit_log

    # 创建所有表
    print("创建数据库表...")
    try:
        Base.metadata.create_all(bind=engine)
        print("✅ 数据库表创建成功")
    except Exception as e:
        print(f"❌ 创建表失败: {e}")
        sys.exit(1)

    # 创建默认管理员
    print()
    print("检查默认管理员账号...")
    from app.models.base import SessionLocal
    from app.models.user import User
    from app.core.security import get_password_hash

    db = SessionLocal()
    try:
        admin = db.query(User).filter(User.username == "admin").first()
        if admin:
            print("ℹ️  管理员账号已存在: admin")
        else:
            admin = User(
                username="admin",
                password_hash=get_password_hash("admin123"),
                nickname="管理员",
                role="admin",
            )
            db.add(admin)
            db.commit()
            print("✅ 默认管理员创建成功")
            print("   用户名: admin")
            print("   密码: admin123")
    except Exception as e:
        print(f"❌ 创建管理员失败: {e}")
        db.rollback()
        sys.exit(1)
    finally:
        db.close()

    print()
    print("=" * 50)
    print("✅ 数据库初始化完成！")
    print("=" * 50)


if __name__ == "__main__":
    main()
