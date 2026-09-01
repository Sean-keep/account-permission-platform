"""
Account Model - 系统账号
"""
from sqlalchemy import Column, Integer, String, Boolean, Text, ForeignKey
from app.models.base import Base, TimestampMixin


class Account(Base, TimestampMixin):
    """系统账号"""
    __tablename__ = "accounts"

    id = Column(Integer, primary_key=True, autoincrement=True)
    username = Column(String(128), nullable=False, index=True)       # 账号名
    system_id = Column(Integer, ForeignKey("systems.id"), nullable=False, index=True)  # 所属系统
    account_type = Column(String(32), default="normal")              # normal / admin / service / shared
    status = Column(String(32), default="active", index=True)        # active / disabled / locked / resigned_pending
    remark = Column(Text, default="")
