"""
System schemas
"""
from typing import Optional
from pydantic import BaseModel


class SystemCreate(BaseModel):
    name: str
    category: str = ""
    owner: str = ""
    url: str = ""
    description: str = ""
    status: str = "active"


class SystemUpdate(BaseModel):
    name: Optional[str] = None
    category: Optional[str] = None
    owner: Optional[str] = None
    url: Optional[str] = None
    description: Optional[str] = None
    status: Optional[str] = None
