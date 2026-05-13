"""initial canonical auth schema

Revision ID: 001_initial_auth_schema
Revises:
Create Date: 2026-05-09
"""
from __future__ import annotations

from pathlib import Path

from alembic import op

revision = "001_initial_auth_schema"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    sql = Path(__file__).resolve().parents[1].joinpath("001_auth_schema.sql").read_text(encoding="utf-8")
    op.execute(sql)


def downgrade() -> None:
    op.execute("drop schema if exists auth cascade")
