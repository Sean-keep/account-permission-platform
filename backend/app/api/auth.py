"""
Auth API
"""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel

from app.models.base import get_db
from app.models.user import User
from app.schemas.auth import LoginRequest
from app.schemas.common import Response
from app.core.security import verify_password, get_password_hash, create_access_token
from app.api.security import get_current_user

router = APIRouter(prefix="/auth", tags=["认证"])


@router.post("/login", response_model=Response)
async def login(request: LoginRequest, db: Session = Depends(get_db)):
    """用户登录"""
    user = db.query(User).filter(User.username == request.username).first()
    if not user or not verify_password(request.password, user.password_hash):
        return Response(code=401, msg="用户名或密码错误")
    if not user.is_active:
        return Response(code=403, msg="账号已禁用")

    token = create_access_token(data={"sub": str(user.id)})
    return Response(msg="登录成功", data={
        "token": token,
        "user": {
            "id": user.id,
            "username": user.username,
            "nickname": user.nickname,
            "role": user.role,
        }
    })


@router.get("/me", response_model=Response)
async def get_me(
    current_user: User = Depends(get_current_user),
):
    """获取当前用户信息"""
    return Response(data={
        "id": current_user.id,
        "username": current_user.username,
        "nickname": current_user.nickname,
        "role": current_user.role,
    })


class ChangePasswordRequest(BaseModel):
    old_password: str
    new_password: str


@router.post("/change-password", response_model=Response)
async def change_password(
    request: ChangePasswordRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """修改密码"""
    if not verify_password(request.old_password, current_user.password_hash):
        return Response(code=400, msg="原密码错误")
    if len(request.new_password) < 6:
        return Response(code=400, msg="新密码长度不能少于6位")
    current_user.password_hash = get_password_hash(request.new_password)
    db.commit()
    from app.api.audit_logs import record_audit_log
    record_audit_log(db, current_user.username, "update", "user", current_user.id, current_user.username, "修改密码")
    return Response(msg="密码修改成功")
