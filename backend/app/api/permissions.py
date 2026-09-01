"""
Permissions API
"""
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.models.base import get_db
from app.models.user import User
from app.models.permission import Permission
from app.models.system import System
from app.api.security import get_current_user
from app.schemas.permission import PermissionCreate, PermissionUpdate
from app.schemas.common import Response, PaginatedResponse, PaginatedData
from app.services.audit_service import record_audit_log

router = APIRouter(prefix="/permissions", tags=["权限管理"])


def _to_dict(p: Permission, system_name: str = "") -> dict:
    return {
        "id": p.id,
        "name": p.name,
        "code": p.code,
        "system_id": p.system_id,
        "system_name": system_name,
        "category": p.category,
        "description": p.description,
        "created_at": str(p.created_at) if p.created_at else "",
    }


@router.get("", response_model=PaginatedResponse)
async def list_permissions(
    keyword: str = Query(default=""),
    system_id: int = Query(default=0),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=10, le=200),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """权限列表"""
    query = db.query(Permission)
    if keyword:
        query = query.filter(
            (Permission.name.like(f"%{keyword}%")) | (Permission.code.like(f"%{keyword}%"))
        )
    if system_id:
        query = query.filter(Permission.system_id == system_id)

    total = query.count()
    rows = query.order_by(Permission.id.desc()).offset((page - 1) * page_size).limit(page_size).all()

    system_ids = list(set(r.system_id for r in rows))
    systems = {s.id: s.name for s in db.query(System).filter(System.id.in_(system_ids)).all()} if system_ids else {}

    return PaginatedResponse(data=PaginatedData(total=total, page=page, page_size=page_size, items=[_to_dict(r, systems.get(r.system_id, "")) for r in rows]))


@router.post("", response_model=Response)
async def create_permission(
    request: PermissionCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """新建权限"""
    system = db.query(System).filter(System.id == request.system_id).first()
    if not system:
        return Response(code=400, msg="所属系统不存在")

    p = Permission(**request.model_dump())
    db.add(p)
    db.commit()
    db.refresh(p)
    record_audit_log(db, current_user.username, "create", "permission", p.id, p.name, f"新建权限: {p.name} (系统: {system.name})")
    return Response(msg="创建成功", data=_to_dict(p, system.name))


@router.put("/{pid}", response_model=Response)
async def update_permission(
    pid: int,
    request: PermissionUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """更新权限"""
    p = db.query(Permission).filter(Permission.id == pid).first()
    if not p:
        return Response(code=404, msg="权限不存在")

    update_data = request.model_dump(exclude_unset=True)
    for k, v in update_data.items():
        setattr(p, k, v)
    db.commit()
    db.refresh(p)
    system = db.query(System).filter(System.id == p.system_id).first()
    record_audit_log(db, current_user.username, "update", "permission", p.id, p.name, f"更新权限: {list(update_data.keys())}")
    return Response(msg="更新成功", data=_to_dict(p, system.name if system else ""))


@router.delete("/{pid}", response_model=Response)
async def delete_permission(
    pid: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """删除权限"""
    p = db.query(Permission).filter(Permission.id == pid).first()
    if not p:
        return Response(code=404, msg="权限不存在")

    from app.models.relation import AccountPermission
    grant_count = db.query(AccountPermission).filter(AccountPermission.permission_id == pid, AccountPermission.status == "active").count()
    if grant_count > 0:
        return Response(code=400, msg=f"该权限还有 {grant_count} 个账号在使用，请先撤销")

    name = p.name
    db.delete(p)
    db.commit()
    record_audit_log(db, current_user.username, "delete", "permission", pid, name, f"删除权限: {name}")
    return Response(msg="删除成功")


@router.get("/all/list", response_model=Response)
async def list_all_permissions(
    system_id: int = Query(default=0),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """获取所有权限（下拉选择用）"""
    query = db.query(Permission)
    if system_id:
        query = query.filter(Permission.system_id == system_id)
    rows = query.order_by(Permission.name).all()
    return Response(data=[{"id": p.id, "name": p.name, "code": p.code, "system_id": p.system_id} for p in rows])
