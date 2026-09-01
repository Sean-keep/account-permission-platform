"""
Account schemas
"""
from typing import Optional
from pydantic import BaseModel


class AccountCreate(BaseModel):
    username: str
    system_id: int
    account_type: str = "normal"
    status: str = "active"
    remark: str = ""


class AccountUpdate(BaseModel):
    username: Optional[str] = None
    system_id: Optional[int] = None
    account_type: Optional[str] = None
    status: Optional[str] = None
    remark: Optional[str] = None
