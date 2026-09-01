"""
Personnel schemas
"""
from typing import Optional
from pydantic import BaseModel


class PersonnelCreate(BaseModel):
    name: str
    employee_id: str
    department: str = ""
    position: str = ""
    email: str = ""
    phone: str = ""
    status: str = "active"
    entry_date: Optional[str] = None
    remark: str = ""


class PersonnelUpdate(BaseModel):
    name: Optional[str] = None
    employee_id: Optional[str] = None
    department: Optional[str] = None
    position: Optional[str] = None
    email: Optional[str] = None
    phone: Optional[str] = None
    status: Optional[str] = None
    entry_date: Optional[str] = None
    resign_date: Optional[str] = None
    remark: Optional[str] = None


class ResignRequest(BaseModel):
    """离职处理请求"""
    resign_date: str
    revoke_all_permissions: bool = True
    disable_accounts: bool = True
    remark: str = ""
