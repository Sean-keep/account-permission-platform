"""
Audit Log Model - 审计日志
"""
from sqlalchemy import Column, Integer, String, Text
from app.models.base import Base, TimestampMixin


class AuditLog(Base, TimestampMixin):
    """审计日志"""
    __tablename__ = "audit_logs"

    id = Column(Integer, primary_key=True, autoincrement=True)
    operator = Column(String(64), nullable=False, index=True)       # 操作人
    action = Column(String(64), nullable=False, index=True)         # 操作类型: create/update/delete/bind/unbind/revoke
    target_type = Column(String(64), nullable=False, index=True)    # 操作对象类型: personnel/system/account/permission
    target_id = Column(Integer, default=0)                          # 操作对象ID
    target_name = Column(String(128), default="")                   # 操作对象名称
    detail = Column(Text, default="")                               # 详细变更内容
    ip_address = Column(String(64), default="")                     # 操作IP
