"""
Audit Log Service
"""
from sqlalchemy.orm import Session
from app.models.audit_log import AuditLog


def record_audit_log(
    db: Session,
    operator: str,
    action: str,
    target_type: str,
    target_id: int = 0,
    target_name: str = "",
    detail: str = "",
    ip_address: str = "",
):
    """Record an audit log entry"""
    log = AuditLog(
        operator=operator,
        action=action,
        target_type=target_type,
        target_id=target_id,
        target_name=target_name,
        detail=detail,
        ip_address=ip_address,
    )
    db.add(log)
    db.commit()
    return log
