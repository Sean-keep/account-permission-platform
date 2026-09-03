"""
Application Configuration
"""
import os
from functools import lru_cache
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    # Application
    APP_NAME: str = "人员账号与权限台账管理平台"
    APP_VERSION: str = "1.0.0"
    DEBUG: bool = False

    # Database
    MYSQL_HOST: str = "localhost"
    MYSQL_PORT: int = 3306
    MYSQL_USER: str = "root"
    MYSQL_PASSWORD: str = ""
    MYSQL_DATABASE: str = "account_permission"

    @property
    def DATABASE_URL(self) -> str:
        return (
            f"mysql+pymysql://{self.MYSQL_USER}:{self.MYSQL_PASSWORD}"
            f"@{self.MYSQL_HOST}:{self.MYSQL_PORT}/{self.MYSQL_DATABASE}"
            "?charset=utf8mb4"
        )

    # JWT
    SECRET_KEY: str = "account-permission-platform-secret-key-min-32-chars"
    JWT_SECRET_KEY: str = "jwt-secret-key-for-account-permission-platform"
    JWT_ALGORITHM: str = "HS256"
    JWT_EXPIRE_MINUTES: int = 480

    # CORS
    CORS_ORIGINS: list[str] = ["*"]

    class Config:
        # 优先读取 backend/.env 文件
        env_file = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), ".env")
        extra = "ignore"


@lru_cache()
def get_settings() -> Settings:
    return Settings()


settings = get_settings()

# 调试信息：显示实际使用的数据库配置
if os.environ.get("DEBUG_DB"):
    print(f"[Config] MYSQL_HOST: {settings.MYSQL_HOST}")
    print(f"[Config] MYSQL_PORT: {settings.MYSQL_PORT}")
    print(f"[Config] MYSQL_USER: {settings.MYSQL_USER}")
    print(f"[Config] MYSQL_DATABASE: {settings.MYSQL_DATABASE}")
    print(f"[Config] DATABASE_URL: {settings.DATABASE_URL}")
