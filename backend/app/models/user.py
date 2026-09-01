"""
System User Model - for platform login
"""
from sqlalchemy import Column, Integer, String, Boolean
from app.models.base import Base, TimestampMixin


class User(Base, TimestampMixin):
    """Platform user (admin/operator)"""
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, autoincrement=True)
    username = Column(String(64), unique=True, nullable=False, index=True)
    password_hash = Column(String(128), nullable=False)
    nickname = Column(String(64), default="")
    role = Column(String(32), default="operator")  # admin / operator / viewer
    is_active = Column(Boolean, default=True)
