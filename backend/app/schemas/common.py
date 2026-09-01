"""
Common schemas for API responses
"""
from __future__ import annotations
from typing import Any, Generic, Optional, TypeVar
from pydantic import BaseModel

T = TypeVar("T")


class Response(BaseModel, Generic[T]):
    code: int = 200
    msg: str = "success"
    data: Optional[T] = None


class PaginatedData(BaseModel, Generic[T]):
    total: int = 0
    page: int = 1
    page_size: int = 20
    items: list[T] = []


class PaginatedResponse(BaseModel, Generic[T]):
    code: int = 200
    msg: str = "success"
    data: Optional[PaginatedData[T]] = None
