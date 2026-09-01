"""
Accounts API
"""
from fastapi import APIRouter, Depends, Query, UploadFile, File
from sqlalchemy.orm import Session
import csv
import io

from app.models.base import get_db
from app.models.user import User
from app.models.account import Account
from app.models.system import System
from app.models.relation import PersonnelAccount, AccountPermission
from app.api.security import get_current_user
from app.schemas.account import AccountCreate, AccountUpdate
from app.schemas.common import Response, PaginatedResponse, PaginatedData
from app.services.audit_service import record_audit_log

router = APIRouter(prefix="/accounts", tags=["账号管理"])


def _to_dict(a: Account, system_name: str = "") -> dict:
    return {
        "id": a.id,
        "username": a.username,
        "system_id": a.system_id,
        "system_name": system_name,
        "account_type": a.account_type,
        "status": a.status,
        "remark": a.remark,
        "created_at": str(a.created_at) if a.created_at else "",
        "updated_at": str(a.updated_at) if a.updated_at else "",
    }


@router.get("", response_model=PaginatedResponse)
async def list_accounts(
    keyword: str = Query(default=""),
    system_id: int = Query(default=0),
    status: str = Query(default=""),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=10, le=200),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """账号列表"""
    query = db.query(Account)
    if keyword:
        query = query.filter(Account.username.like(f"%{keyword}%"))
    if system_id:
        query = query.filter(Account.system_id == system_id)
    if status:
        query = query.filter(Account.status == status)

    total = query.count()
    rows = query.order_by(Account.id.desc()).offset((page - 1) * page_size).limit(page_size).all()

    # Batch load system names
    system_ids = list(set(r.system_id for r in rows))
    systems = {s.id: s.name for s in db.query(System).filter(System.id.in_(system_ids)).all()} if system_ids else {}

    return PaginatedResponse(data=PaginatedData(total=total, page=page, page_size=page_size, items=[_to_dict(r, systems.get(r.system_id, "")) for r in rows]))


@router.post("", response_model=Response)
async def create_account(
    request: AccountCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """新建账号"""
    # Check system exists
    system = db.query(System).filter(System.id == request.system_id).first()
    if not system:
        return Response(code=400, msg="所属系统不存在")

    a = Account(**request.model_dump())
    db.add(a)
    db.commit()
    db.refresh(a)
    record_audit_log(db, current_user.username, "create", "account", a.id, a.username, f"新建账号: {a.username} (系统: {system.name})")
    return Response(msg="创建成功", data=_to_dict(a, system.name))


@router.get("/{aid}", response_model=Response)
async def get_account(aid: int, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """获取账号详情"""
    a = db.query(Account).filter(Account.id == aid).first()
    if not a:
        return Response(code=404, msg="账号不存在")
    system = db.query(System).filter(System.id == a.system_id).first()
    return Response(data=_to_dict(a, system.name if system else ""))


@router.put("/{aid}", response_model=Response)
async def update_account(
    aid: int,
    request: AccountUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """更新账号"""
    a = db.query(Account).filter(Account.id == aid).first()
    if not a:
        return Response(code=404, msg="账号不存在")

    update_data = request.model_dump(exclude_unset=True)
    for k, v in update_data.items():
        setattr(a, k, v)
    db.commit()
    db.refresh(a)
    system = db.query(System).filter(System.id == a.system_id).first()
    record_audit_log(db, current_user.username, "update", "account", a.id, a.username, f"更新账号: {list(update_data.keys())}")
    return Response(msg="更新成功", data=_to_dict(a, system.name if system else ""))


@router.delete("/{aid}", response_model=Response)
async def delete_account(
    aid: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """删除账号"""
    a = db.query(Account).filter(Account.id == aid).first()
    if not a:
        return Response(code=404, msg="账号不存在")

    # Count active bindings before deletion
    active_binds = db.query(PersonnelAccount).filter(PersonnelAccount.account_id == aid, PersonnelAccount.status == "active").count()

    # Delete all personnel bindings
    db.query(PersonnelAccount).filter(PersonnelAccount.account_id == aid).delete()

    # Delete all permissions
    db.query(AccountPermission).filter(AccountPermission.account_id == aid).delete()

    username = a.username
    db.delete(a)
    db.commit()
    record_audit_log(db, current_user.username, "delete", "account", aid, username, f"删除账号: {username} (自动解绑 {active_binds} 个人员)")
    return Response(msg=f"删除成功" + (f"，已自动解绑 {active_binds} 个人员" if active_binds else ""))


@router.get("/{aid}/permissions", response_model=Response)
async def get_account_permissions(
    aid: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """获取账号的权限列表"""
    a = db.query(Account).filter(Account.id == aid).first()
    if not a:
        return Response(code=404, msg="账号不存在")

    from app.models.permission import Permission
    links = db.query(AccountPermission).filter(AccountPermission.account_id == aid).all()
    perm_ids = [l.permission_id for l in links]
    perms = {p.id: p for p in db.query(Permission).filter(Permission.id.in_(perm_ids)).all()} if perm_ids else {}

    result = []
    for link in links:
        perm = perms.get(link.permission_id)
        if perm:
            result.append({
                "link_id": link.id,
                "permission_id": perm.id,
                "permission_name": perm.name,
                "permission_code": perm.code,
                "category": perm.category,
                "granted_date": link.granted_date,
                "expire_date": link.expire_date,
                "status": link.status,
                "granted_by": link.granted_by,
            })
    return Response(data=result)


@router.post("/import", response_model=Response)
async def import_accounts(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """批量导入账号 (CSV格式: 账号名,系统名称,账号类型,备注)"""
    if not file.filename.endswith('.csv'):
        return Response(code=400, msg="请上传 CSV 文件")

    try:
        content = await file.read()
        # Try different encodings
        for encoding in ['utf-8-sig', 'utf-8', 'gbk', 'gb2312']:
            try:
                text = content.decode(encoding)
                break
            except UnicodeDecodeError:
                continue
        else:
            return Response(code=400, msg="文件编码无法识别，请使用 UTF-8 编码")

        reader = csv.reader(io.StringIO(text))
        header = next(reader, None)
        if not header:
            return Response(code=400, msg="文件为空")

        # Get all systems for mapping
        systems = {s.name: s for s in db.query(System).all()}

        success_count = 0
        fail_count = 0
        errors = []

        for i, row in enumerate(reader, start=2):
            if len(row) < 2:
                errors.append(f"第{i}行: 数据不完整")
                fail_count += 1
                continue

            username = row[0].strip()
            system_name = row[1].strip()
            account_type = row[2].strip() if len(row) > 2 and row[2].strip() else "normal"
            remark = row[3].strip() if len(row) > 3 else ""

            if not username or not system_name:
                errors.append(f"第{i}行: 账号名或系统名称为空")
                fail_count += 1
                continue

            system = systems.get(system_name)
            if not system:
                errors.append(f"第{i}行: 系统 '{system_name}' 不存在")
                fail_count += 1
                continue

            # Check duplicate
            exists = db.query(Account).filter(
                Account.username == username,
                Account.system_id == system.id
            ).first()
            if exists:
                errors.append(f"第{i}行: 账号 '{username}' 在系统 '{system_name}' 中已存在")
                fail_count += 1
                continue

            # Validate account_type
            valid_types = ['normal', 'admin', 'service', 'shared']
            if account_type not in valid_types:
                errors.append(f"第{i}行: 账号类型 '{account_type}' 无效，可选: {', '.join(valid_types)}")
                fail_count += 1
                continue

            account = Account(
                username=username,
                system_id=system.id,
                account_type=account_type,
                status="active",
                remark=remark,
            )
            db.add(account)
            success_count += 1

        db.commit()

        # Audit log
        record_audit_log(
            db, current_user.username, "import", "account", 0, "",
            f"批量导入账号: 成功 {success_count} 个, 失败 {fail_count} 个"
        )

        msg = f"导入完成: 成功 {success_count} 个"
        if fail_count > 0:
            msg += f", 失败 {fail_count} 个"

        return Response(msg=msg, data={
            "success": success_count,
            "fail": fail_count,
            "errors": errors[:20],  # Only return first 20 errors
        })

    except Exception as e:
        return Response(code=500, msg=f"导入失败: {str(e)}")


@router.get("/template/download", response_model=Response)
async def download_template(
    current_user: User = Depends(get_current_user),
):
    """下载导入模板"""
    return Response(data={
        "filename": "账号导入模板.csv",
        "content": "账号名,系统名称,账号类型,备注\n示例用户,OA系统,normal,示例备注\n",
        "headers": ["账号名", "系统名称", "账号类型", "备注"],
        "tips": [
            "账号名: 必填，账号的登录名称",
            "系统名称: 必填，必须是已存在的系统名称",
            "账号类型: 可选，normal/admin/service/shared，默认 normal",
            "备注: 可选",
        ]
    })
