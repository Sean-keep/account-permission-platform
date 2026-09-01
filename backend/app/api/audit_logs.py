"""
Audit Logs API
"""
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.models.base import get_db
from app.models.user import User
from app.models.audit_log import AuditLog
from app.api.security import get_current_user
from app.schemas.common import Response, PaginatedResponse, PaginatedData

router = APIRouter(prefix="/audit-logs", tags=["审计日志"])


def _to_dict(log: AuditLog) -> dict:
    return {
        "id": log.id,
        "operator": log.operator,
        "action": log.action,
        "target_type": log.target_type,
        "target_id": log.target_id,
        "target_name": log.target_name,
        "detail": log.detail,
        "ip_address": log.ip_address,
        "created_at": str(log.created_at) if log.created_at else "",
    }


@router.get("", response_model=PaginatedResponse)
async def list_audit_logs(
    operator: str = Query(default=""),
    action: str = Query(default=""),
    target_type: str = Query(default=""),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=10, le=200),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """审计日志列表"""
    query = db.query(AuditLog)
    if operator:
        query = query.filter(AuditLog.operator.like(f"%{operator}%"))
    if action:
        query = query.filter(AuditLog.action == action)
    if target_type:
        query = query.filter(AuditLog.target_type == target_type)

    total = query.count()
    rows = query.order_by(AuditLog.id.desc()).offset((page - 1) * page_size).limit(page_size).all()
    return PaginatedResponse(data=PaginatedData(total=total, page=page, page_size=page_size, items=[_to_dict(r) for r in rows]))
