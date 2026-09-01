"""
Personnel Model - 人员信息
"""
from sqlalchemy import Column, Integer, String, Boolean, Date, Text
from app.models.base import Base, TimestampMixin


class Personnel(Base, TimestampMixin):
    """员工/人员信息"""
    __tablename__ = "personnel"

    id = Column(Integer, primary_key=True, autoincrement=True)
    name = Column(String(64), nullable=False, index=True)           # 姓名
    employee_id = Column(String(64), unique=True, nullable=False, index=True)  # 工号
    department = Column(String(128), default="", index=True)        # 部门
    position = Column(String(128), default="")                      # 职位
    email = Column(String(128), default="")                         # 邮箱
    phone = Column(String(32), default="")                          # 手机
    status = Column(String(32), default="active", index=True)       # active / resigned / suspended
    entry_date = Column(Date, nullable=True)                        # 入职日期
    resign_date = Column(Date, nullable=True)                       # 离职日期
    remark = Column(Text, default="")                               # 备注
