"""
Relations API - 人员-账号绑定, 账号-权限授予
"""
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.models.base import get_db
from app.models.user import User
from app.models.personnel import Personnel
from app.models.account import Account
from app.models.permission import Permission
from app.models.system import System
from app.models.relation import PersonnelAccount, AccountPermission
from app.api.security import get_current_user
from app.schemas.relation import PersonnelAccountBind, AccountPermissionGrant, BatchRevokeRequest
from app.schemas.common import Response
from app.services.audit_service import record_audit_log

router = APIRouter(prefix="/relations", tags=["关系管理"])


# ==================== 人员-账号 绑定 ====================

@router.post("/bind-account", response_model=Response)
async def bind_personnel_account(
    request: PersonnelAccountBind,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """绑定人员-账号"""
    personnel = db.query(Personnel).filter(Personnel.id == request.personnel_id).first()
    if not personnel:
        return Response(code=404, msg="人员不存在")
    account = db.query(Account).filter(Account.id == request.account_id).first()
    if not account:
        return Response(code=404, msg="账号不存在")

    # Check duplicate binding
    existing = db.query(PersonnelAccount).filter(
        PersonnelAccount.personnel_id == request.personnel_id,
        PersonnelAccount.account_id == request.account_id,
        PersonnelAccount.status == "active",
    ).first()
    if existing:
        return Response(code=400, msg="该绑定关系已存在")

    bind = PersonnelAccount(**request.model_dump())
    db.add(bind)
    db.commit()
    db.refresh(bind)

    system = db.query(System).filter(System.id == account.system_id).first()
    record_audit_log(
        db, current_user.username, "bind", "personnel_account", bind.id,
        f"{personnel.name} - {account.username}",
        f"绑定人员 [{personnel.name}] 到账号 [{account.username}] (系统: {system.name if system else ''})"
    )
    return Response(msg="绑定成功")


@router.post("/unbind-account", response_model=Response)
async def unbind_personnel_account(
    bind_id: int = Query(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """解绑人员-账号"""
    bind = db.query(PersonnelAccount).filter(PersonnelAccount.id == bind_id).first()
    if not bind:
        return Response(code=404, msg="绑定关系不存在")
    if bind.status != "active":
        return Response(code=400, msg="该绑定已解除")

    from datetime import datetime
    bind.status = "unbound"
    bind.unbind_date = datetime.now().strftime("%Y-%m-%d")
    db.commit()

    personnel = db.query(Personnel).filter(Personnel.id == bind.personnel_id).first()
    account = db.query(Account).filter(Account.id == bind.account_id).first()
    record_audit_log(
        db, current_user.username, "unbind", "personnel_account", bind.id,
        f"{personnel.name if personnel else ''} - {account.username if account else ''}",
        f"解绑人员-账号关系"
    )
    return Response(msg="解绑成功")


# ==================== 账号-权限 授予 ====================

@router.post("/grant-permission", response_model=Response)
async def grant_account_permission(
    request: AccountPermissionGrant,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """授予账号权限"""
    account = db.query(Account).filter(Account.id == request.account_id).first()
    if not account:
        return Response(code=404, msg="账号不存在")
    permission = db.query(Permission).filter(Permission.id == request.permission_id).first()
    if not permission:
        return Response(code=404, msg="权限不存在")

    # Check duplicate
    existing = db.query(AccountPermission).filter(
        AccountPermission.account_id == request.account_id,
        AccountPermission.permission_id == request.permission_id,
        AccountPermission.status == "active",
    ).first()
    if existing:
        return Response(code=400, msg="该权限已授予")

    link = AccountPermission(**request.model_dump())
    db.add(link)
    db.commit()
    db.refresh(link)

    record_audit_log(
        db, current_user.username, "grant", "account_permission", link.id,
        f"{account.username} - {permission.name}",
        f"授予账号 [{account.username}] 权限 [{permission.name}]"
    )
    return Response(msg="授权成功")


@router.post("/revoke-permission", response_model=Response)
async def revoke_account_permission(
    link_id: int = Query(...),
    reason: str = Query(default=""),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """撤销账号权限"""
    link = db.query(AccountPermission).filter(AccountPermission.id == link_id).first()
    if not link:
        return Response(code=404, msg="授权记录不存在")
    if link.status != "active":
        return Response(code=400, msg="该权限已撤销")

    link.status = "revoked"
    link.remark = reason or "手动撤销"
    db.commit()

    account = db.query(Account).filter(Account.id == link.account_id).first()
    permission = db.query(Permission).filter(Permission.id == link.permission_id).first()
    record_audit_log(
        db, current_user.username, "revoke", "account_permission", link.id,
        f"{account.username if account else ''} - {permission.name if permission else ''}",
        f"撤销权限，原因: {reason or '手动撤销'}"
    )
    return Response(msg="撤销成功")


@router.post("/batch-revoke", response_model=Response)
async def batch_revoke_permissions(
    request: BatchRevokeRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """批量撤销权限"""
    account = db.query(Account).filter(Account.id == request.account_id).first()
    if not account:
        return Response(code=404, msg="账号不存在")

    revoked = 0
    for perm_id in request.permission_ids:
        link = db.query(AccountPermission).filter(
            AccountPermission.account_id == request.account_id,
            AccountPermission.permission_id == perm_id,
            AccountPermission.status == "active",
        ).first()
        if link:
            link.status = "revoked"
            link.remark = request.reason or "批量撤销"
            revoked += 1

    db.commit()
    record_audit_log(
        db, current_user.username, "batch_revoke", "account_permission", request.account_id,
        account.username,
        f"批量撤销 {revoked} 项权限，原因: {request.reason or '批量操作'}"
    )
    return Response(msg=f"成功撤销 {revoked} 项权限")
