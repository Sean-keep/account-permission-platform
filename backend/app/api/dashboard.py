"""
Dashboard API - 统计概览
"""
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from sqlalchemy import func

from app.models.base import get_db
from app.models.user import User
from app.models.personnel import Personnel
from app.models.system import System
from app.models.account import Account
from app.models.permission import Permission
from app.models.relation import PersonnelAccount, AccountPermission
from app.models.audit_log import AuditLog
from app.api.security import get_current_user
from app.schemas.common import Response

router = APIRouter(prefix="/dashboard", tags=["仪表盘"])


@router.get("/stats", response_model=Response)
async def get_stats(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """获取统计数据"""
    # 人员统计
    total_personnel = db.query(Personnel).count()
    active_personnel = db.query(Personnel).filter(Personnel.status == "active").count()
    resigned_personnel = db.query(Personnel).filter(Personnel.status == "resigned").count()

    # 系统统计
    total_systems = db.query(System).count()
    active_systems = db.query(System).filter(System.status == "active").count()

    # 账号统计
    total_accounts = db.query(Account).count()
    active_accounts = db.query(Account).filter(Account.status == "active").count()
    resigned_pending = db.query(Account).filter(Account.status == "resigned_pending").count()

    # 绑定统计
    personnel_account_binds = db.query(PersonnelAccount).filter(PersonnelAccount.status == "active").count()
    account_permission_binds = db.query(AccountPermission).filter(AccountPermission.status == "active").count()

    # 部门分布
    dept_stats = (
        db.query(Personnel.department, func.count(Personnel.id))
        .filter(Personnel.status == "active")
        .group_by(Personnel.department)
        .order_by(func.count(Personnel.id).desc())
        .limit(8)
        .all()
    )

    # 最近审计日志
    recent_logs = db.query(AuditLog).order_by(AuditLog.id.desc()).limit(10).all()

    return Response(data={
        "personnel": {
            "total": total_personnel,
            "active": active_personnel,
            "resigned": resigned_personnel,
        },
        "systems": {
            "total": total_systems,
            "active": active_systems,
        },
        "accounts": {
            "total": total_accounts,
            "active": active_accounts,
            "resigned_pending": resigned_pending,
        },
        "bindings": {
            "personnel_account": personnel_account_binds,
            "account_permission": account_permission_binds,
        },
        "departments": [
            {"department": dept or "未分配", "count": count}
            for dept, count in dept_stats
        ],
        "recent_logs": [
            {
                "id": log.id,
                "operator": log.operator,
                "action": log.action,
                "target_type": log.target_type,
                "target_name": log.target_name,
                "detail": log.detail[:100] if log.detail else "",
                "created_at": str(log.created_at) if log.created_at else "",
            }
            for log in recent_logs
        ],
    })


@router.get("/departments", response_model=Response)
async def get_departments(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """获取部门列表（用于筛选下拉）"""
    rows = db.query(Personnel.department).distinct().filter(Personnel.department != "").all()
    return Response(data=[r[0] for r in rows])
