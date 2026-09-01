"""
System Model - 业务系统
"""
from sqlalchemy import Column, Integer, String, Text
from app.models.base import Base, TimestampMixin


class System(Base, TimestampMixin):
    """业务系统/应用"""
    __tablename__ = "systems"

    id = Column(Integer, primary_key=True, autoincrement=True)
    name = Column(String(128), nullable=False, unique=True, index=True)  # 系统名称
    category = Column(String(64), default="")                            # 分类: OA/财务/运维/开发等
    owner = Column(String(64), default="")                               # 系统负责人
    url = Column(String(256), default="")                                # 系统地址
    description = Column(Text, default="")                               # 描述
    status = Column(String(32), default="active")                        # active / inactive
