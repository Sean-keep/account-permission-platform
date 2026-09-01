"""
Personnel API
"""
from datetime import datetime
from fastapi import APIRouter, Depends, Query, HTTPException
from sqlalchemy.orm import Session

from app.models.base import get_db
from app.models.user import User
from app.models.personnel import Personnel
from app.models.relation import PersonnelAccount, AccountPermission
from app.models.account import Account
from app.api.security import get_current_user
from app.schemas.personnel import PersonnelCreate, PersonnelUpdate, ResignRequest
from app.schemas.common import Response, PaginatedResponse, PaginatedData
from app.services.audit_service import record_audit_log

router = APIRouter(prefix="/personnel", tags=["人员管理"])


def _to_dict(p: Personnel) -> dict:
    return {
        "id": p.id,
        "name": p.name,
        "employee_id": p.employee_id,
        "department": p.department,
        "position": p.position,
        "email": p.email,
        "phone": p.phone,
        "status": p.status,
        "entry_date": str(p.entry_date) if p.entry_date else "",
        "resign_date": str(p.resign_date) if p.resign_date else "",
        "remark": p.remark,
        "created_at": str(p.created_at) if p.created_at else "",
        "updated_at": str(p.updated_at) if p.updated_at else "",
    }


@router.get("", response_model=PaginatedResponse)
async def list_personnel(
    keyword: str = Query(default=""),
    status: str = Query(default=""),
    department: str = Query(default=""),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=10, le=200),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """人员列表"""
    query = db.query(Personnel)
    if keyword:
        query = query.filter(
            (Personnel.name.like(f"%{keyword}%")) | (Personnel.employee_id.like(f"%{keyword}%"))
        )
    if status:
        query = query.filter(Personnel.status == status)
    if department:
        query = query.filter(Personnel.department.like(f"%{department}%"))

    total = query.count()
    rows = query.order_by(Personnel.id.desc()).offset((page - 1) * page_size).limit(page_size).all()
    return PaginatedResponse(data=PaginatedData(total=total, page=page, page_size=page_size, items=[_to_dict(r) for r in rows]))


@router.post("", response_model=Response)
async def create_personnel(
    request: PersonnelCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """新建人员"""
    if db.query(Personnel).filter(Personnel.employee_id == request.employee_id).first():
        return Response(code=400, msg="工号已存在")

    data = request.model_dump()
    # Handle empty date strings - convert to None
    if not data.get("entry_date"):
        data["entry_date"] = None
    p = Personnel(**data)
    if request.entry_date:
        p.entry_date = datetime.strptime(request.entry_date, "%Y-%m-%d").date()
    db.add(p)
    db.commit()
    db.refresh(p)

    record_audit_log(db, current_user.username, "create", "personnel", p.id, p.name, f"新建人员: {p.name}({p.employee_id})")
    return Response(msg="创建成功", data=_to_dict(p))


@router.get("/{pid}", response_model=Response)
async def get_personnel(pid: int, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """获取人员详情"""
    p = db.query(Personnel).filter(Personnel.id == pid).first()
    if not p:
        return Response(code=404, msg="人员不存在")
    return Response(data=_to_dict(p))


@router.put("/{pid}", response_model=Response)
async def update_personnel(
    pid: int,
    request: PersonnelUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """更新人员"""
    p = db.query(Personnel).filter(Personnel.id == pid).first()
    if not p:
        return Response(code=404, msg="人员不存在")

    update_data = request.model_dump(exclude_unset=True)
    if "entry_date" in update_data and update_data["entry_date"]:
        update_data["entry_date"] = datetime.strptime(update_data["entry_date"], "%Y-%m-%d").date()
    if "resign_date" in update_data and update_data["resign_date"]:
        update_data["resign_date"] = datetime.strptime(update_data["resign_date"], "%Y-%m-%d").date()

    for k, v in update_data.items():
        setattr(p, k, v)
    db.commit()
    db.refresh(p)

    record_audit_log(db, current_user.username, "update", "personnel", p.id, p.name, f"更新人员信息: {list(update_data.keys())}")
    return Response(msg="更新成功", data=_to_dict(p))


@router.delete("/{pid}", response_model=Response)
async def delete_personnel(
    pid: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """删除人员"""
    p = db.query(Personnel).filter(Personnel.id == pid).first()
    if not p:
        return Response(code=404, msg="人员不存在")

    # Count active bindings before deletion
    active_binds = db.query(PersonnelAccount).filter(PersonnelAccount.personnel_id == pid, PersonnelAccount.status == "active").count()

    # Delete all account bindings (both active and unbound)
    db.query(PersonnelAccount).filter(PersonnelAccount.personnel_id == pid).delete()

    name = p.name
    db.delete(p)
    db.commit()
    record_audit_log(db, current_user.username, "delete", "personnel", pid, name, f"删除人员: {name} (自动解绑 {active_binds} 个账号)")
    return Response(msg=f"删除成功" + (f"，已自动解绑 {active_binds} 个账号" if active_binds else ""))


@router.post("/{pid}/resign", response_model=Response)
async def resign_personnel(
    pid: int,
    request: ResignRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """离职处理 - 权限回收"""
    p = db.query(Personnel).filter(Personnel.id == pid).first()
    if not p:
        return Response(code=404, msg="人员不存在")
    if p.status == "resigned":
        return Response(code=400, msg="该人员已离职")

    resign_date = datetime.strptime(request.resign_date, "%Y-%m-%d").date()
    p.status = "resigned"
    p.resign_date = resign_date

    actions_taken = []

    # Get all active bindings
    binds = db.query(PersonnelAccount).filter(
        PersonnelAccount.personnel_id == pid,
        PersonnelAccount.status == "active"
    ).all()

    for bind in binds:
        account = db.query(Account).filter(Account.id == bind.account_id).first()
        if not account:
            continue

        # Unbind personnel-account
        bind.status = "unbound"
        bind.unbind_date = request.resign_date
        actions_taken.append(f"解绑账号: {account.username}")

        # Disable account if requested
        if request.disable_accounts:
            account.status = "resigned_pending"
            actions_taken.append(f"标记账号待处理: {account.username}")

        # Revoke all permissions if requested
        if request.revoke_all_permissions:
            perms = db.query(AccountPermission).filter(
                AccountPermission.account_id == account.id,
                AccountPermission.status == "active"
            ).all()
            for perm in perms:
                perm.status = "revoked"
                perm.remark = f"人员离职回收 ({request.remark})"
            if perms:
                actions_taken.append(f"撤销 {account.username} 的 {len(perms)} 项权限")

    db.commit()

    detail = f"离职处理完成，操作: {'; '.join(actions_taken)}" if actions_taken else "离职处理完成，无需回收操作"
    record_audit_log(db, current_user.username, "resign", "personnel", p.id, p.name, detail)
    return Response(msg="离职处理完成", data={"actions": actions_taken})


@router.get("/{pid}/accounts", response_model=Response)
async def get_personnel_accounts(
    pid: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """获取人员绑定的账号列表"""
    p = db.query(Personnel).filter(Personnel.id == pid).first()
    if not p:
        return Response(code=404, msg="人员不存在")

    binds = db.query(PersonnelAccount).filter(PersonnelAccount.personnel_id == pid).all()
    result = []
    for bind in binds:
        account = db.query(Account).filter(Account.id == bind.account_id).first()
        if account:
            from app.models.system import System
            sys_obj = db.query(System).filter(System.id == account.system_id).first()
            result.append({
                "bind_id": bind.id,
                "bind_type": bind.bind_type,
                "bind_status": bind.status,
                "bind_date": bind.bind_date,
                "unbind_date": bind.unbind_date,
                "account_id": account.id,
                "username": account.username,
                "account_status": account.status,
                "system_id": account.system_id,
                "system_name": sys_obj.name if sys_obj else "",
            })
    return Response(data=result)
