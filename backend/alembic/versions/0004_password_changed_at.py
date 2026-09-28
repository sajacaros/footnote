"""password_changed_at

Revision ID: 0004
Revises: 0003
"""

from alembic import op

revision = "0004"
down_revision = "0003"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("ALTER TABLE users ADD COLUMN password_changed_at timestamptz")


def downgrade() -> None:
    op.execute("ALTER TABLE users DROP COLUMN password_changed_at")
