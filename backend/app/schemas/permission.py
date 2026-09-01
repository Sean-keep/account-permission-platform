"""
Permission schemas
"""
from typing import Optional
from pydantic import BaseModel


class PermissionCreate(BaseModel):
    name: str
    code: str
    system_id: int
    category: str = ""
    description: str = ""


class PermissionUpdate(BaseModel):
    name: Optional[str] = None
    code: Optional[str] = None
    system_id: Optional[int] = None
    category: Optional[str] = None
    description: Optional[str] = None
