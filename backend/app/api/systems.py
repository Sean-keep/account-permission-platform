"""
Systems API
"""
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.models.base import get_db
from app.models.user import User
from app.models.system import System
from app.api.security import get_current_user
from app.schemas.system import SystemCreate, SystemUpdate
from app.schemas.common import Response, PaginatedResponse, PaginatedData
from app.services.audit_service import record_audit_log

router = APIRouter(prefix="/systems", tags=["系统管理"])


def _to_dict(s: System) -> dict:
    return {
        "id": s.id,
        "name": s.name,
        "category": s.category,
        "owner": s.owner,
        "url": s.url,
        "description": s.description,
        "status": s.status,
        "created_at": str(s.created_at) if s.created_at else "",
        "updated_at": str(s.updated_at) if s.updated_at else "",
    }


@router.get("", response_model=PaginatedResponse)
async def list_systems(
    keyword: str = Query(default=""),
    status: str = Query(default=""),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=10, le=200),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """系统列表"""
    query = db.query(System)
    if keyword:
        query = query.filter(System.name.like(f"%{keyword}%"))
    if status:
        query = query.filter(System.status == status)

    total = query.count()
    rows = query.order_by(System.id.desc()).offset((page - 1) * page_size).limit(page_size).all()
    return PaginatedResponse(data=PaginatedData(total=total, page=page, page_size=page_size, items=[_to_dict(r) for r in rows]))


@router.post("", response_model=Response)
async def create_system(
    request: SystemCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """新建系统"""
    if db.query(System).filter(System.name == request.name).first():
        return Response(code=400, msg="系统名称已存在")

    s = System(**request.model_dump())
    db.add(s)
    db.commit()
    db.refresh(s)
    record_audit_log(db, current_user.username, "create", "system", s.id, s.name, f"新建系统: {s.name}")
    return Response(msg="创建成功", data=_to_dict(s))


@router.get("/{sid}", response_model=Response)
async def get_system(sid: int, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """获取系统详情"""
    s = db.query(System).filter(System.id == sid).first()
    if not s:
        return Response(code=404, msg="系统不存在")
    return Response(data=_to_dict(s))


@router.put("/{sid}", response_model=Response)
async def update_system(
    sid: int,
    request: SystemUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """更新系统"""
    s = db.query(System).filter(System.id == sid).first()
    if not s:
        return Response(code=404, msg="系统不存在")

    update_data = request.model_dump(exclude_unset=True)
    for k, v in update_data.items():
        setattr(s, k, v)
    db.commit()
    db.refresh(s)
    record_audit_log(db, current_user.username, "update", "system", s.id, s.name, f"更新系统: {list(update_data.keys())}")
    return Response(msg="更新成功", data=_to_dict(s))


@router.delete("/{sid}", response_model=Response)
async def delete_system(
    sid: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """删除系统"""
    s = db.query(System).filter(System.id == sid).first()
    if not s:
        return Response(code=404, msg="系统不存在")

    from app.models.account import Account
    acct_count = db.query(Account).filter(Account.system_id == sid).count()
    if acct_count > 0:
        return Response(code=400, msg=f"该系统下还有 {acct_count} 个账号，请先清理")

    name = s.name
    db.delete(s)
    db.commit()
    record_audit_log(db, current_user.username, "delete", "system", sid, name, f"删除系统: {name}")
    return Response(msg="删除成功")


@router.get("/{sid}/personnel", response_model=Response)
async def get_system_personnel(
    sid: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """获取系统下的人员列表（通过账号关联）"""
    from app.models.account import Account
    from app.models.relation import PersonnelAccount
    from app.models.personnel import Personnel

    system = db.query(System).filter(System.id == sid).first()
    if not system:
        return Response(code=404, msg="系统不存在")

    # Get all accounts for this system
    accounts = db.query(Account).filter(Account.system_id == sid).all()
    if not accounts:
        return Response(data={"system": _to_dict(system), "personnel": [], "total": 0})

    account_ids = [a.id for a in accounts]
    accounts_map = {a.id: a for a in accounts}

    # Get all personnel bindings for these accounts
    binds = db.query(PersonnelAccount).filter(
        PersonnelAccount.account_id.in_(account_ids),
        PersonnelAccount.status == "active"
    ).all()

    # Get unique personnel IDs
    personnel_ids = list(set(b.personnel_id for b in binds))
    if not personnel_ids:
        return Response(data={"system": _to_dict(system), "personnel": [], "total": 0})

    personnel_map = {p.id: p for p in db.query(Personnel).filter(Personnel.id.in_(personnel_ids)).all()}

    # Build result
    result = []
    for bind in binds:
        p = personnel_map.get(bind.personnel_id)
        a = accounts_map.get(bind.account_id)
        if p and a:
            result.append({
                "personnel_id": p.id,
                "name": p.name,
                "employee_id": p.employee_id,
                "department": p.department,
                "position": p.position,
                "status": p.status,
                "account_id": a.id,
                "username": a.username,
                "account_type": a.account_type,
                "bind_type": bind.bind_type,
            })

    return Response(data={"system": _to_dict(system), "personnel": result, "total": len(result)})


@router.get("/all/list", response_model=Response)
async def list_all_systems(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """获取所有系统（下拉选择用）"""
    rows = db.query(System).filter(System.status == "active").order_by(System.name).all()
    return Response(data=[{"id": s.id, "name": s.name} for s in rows])
