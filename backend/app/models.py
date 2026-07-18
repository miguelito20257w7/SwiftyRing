import enum
import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, Enum, String, func, text
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class RolUsuario(str, enum.Enum):
    admin = "admin"
    operador = "operador"
    profesor = "profesor"


class Usuario(Base):
    __tablename__ = "usuarios"

    id: Mapped[str] = mapped_column(
        String, primary_key=True, default=lambda: str(uuid.uuid4())
    )
    nombre: Mapped[str] = mapped_column(String, nullable=False)
    email: Mapped[str] = mapped_column(String, unique=True, nullable=False)
    password_hash: Mapped[str] = mapped_column(String, nullable=False)
    rol: Mapped[RolUsuario] = mapped_column(
        Enum(RolUsuario, name="rol_usuario"), nullable=False
    )
    activo: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default=text("true")
    )
    creado_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    actualizado_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )