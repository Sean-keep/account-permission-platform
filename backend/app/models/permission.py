"""
Permission Model - 权限定义
"""
from sqlalchemy import Column, Integer, String, Text, ForeignKey
from app.models.base import Base, TimestampMixin


class Permission(Base, TimestampMixin):
    """权限定义"""
    __tablename__ = "permissions"

    id = Column(Integer, primary_key=True, autoincrement=True)
    name = Column(String(128), nullable=False)                       # 权限名称
    code = Column(String(128), nullable=False, index=True)           # 权限编码
    system_id = Column(Integer, ForeignKey("systems.id"), nullable=False, index=True)  # 所属系统
    category = Column(String(64), default="")                        # 权限分类: 功能权限/数据权限/角色
    description = Column(Text, default="")
