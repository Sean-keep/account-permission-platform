"""
Relationship schemas
"""
from typing import Optional
from pydantic import BaseModel


class PersonnelAccountBind(BaseModel):
    """人员-账号绑定"""
    personnel_id: int
    account_id: int
    bind_type: str = "primary"
    bind_date: str = ""
    remark: str = ""


class AccountPermissionGrant(BaseModel):
    """账号-权限授予"""
    account_id: int
    permission_id: int
    granted_date: str = ""
    expire_date: str = ""
    granted_by: str = ""
    remark: str = ""


class BatchRevokeRequest(BaseModel):
    """批量撤销权限"""
    account_id: int
    permission_ids: list[int]
    reason: str = ""
