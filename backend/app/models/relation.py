"""
Relationship Models - 人员-账号 关联, 账号-权限 关联
"""
from sqlalchemy import Column, Integer, String, Text, ForeignKey
from app.models.base import Base, TimestampMixin


class PersonnelAccount(Base, TimestampMixin):
    """人员-账号 关联"""
    __tablename__ = "personnel_accounts"

    id = Column(Integer, primary_key=True, autoincrement=True)
    personnel_id = Column(Integer, ForeignKey("personnel.id"), nullable=False, index=True)
    account_id = Column(Integer, ForeignKey("accounts.id"), nullable=False, index=True)
    bind_type = Column(String(32), default="primary")   # primary / secondary / temporary
    bind_date = Column(String(32), default="")          # 绑定日期
    unbind_date = Column(String(32), default="")        # 解绑日期
    status = Column(String(32), default="active", index=True)  # active / unbound
    remark = Column(Text, default="")


class AccountPermission(Base, TimestampMixin):
    """账号-权限 关联"""
    __tablename__ = "account_permissions"

    id = Column(Integer, primary_key=True, autoincrement=True)
    account_id = Column(Integer, ForeignKey("accounts.id"), nullable=False, index=True)
    permission_id = Column(Integer, ForeignKey("permissions.id"), nullable=False, index=True)
    granted_date = Column(String(32), default="")       # 授权日期
    expire_date = Column(String(32), default="")        # 过期日期(空=永久)
    status = Column(String(32), default="active", index=True)  # active / revoked / expired
    granted_by = Column(String(64), default="")         # 授权人
    remark = Column(Text, default="")
