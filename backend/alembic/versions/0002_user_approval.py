"""user approval and admin

Revision ID: 0002
Revises: 0001
"""

from alembic import op

revision = "0002"
down_revision = "0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 기존 사용자는 이미 쓰고 있던 계정이므로 active로 둔다.
    op.execute("ALTER TABLE users ADD COLUMN status varchar(20) NOT NULL DEFAULT 'active'")
    op.execute("ALTER TABLE users ALTER COLUMN status SET DEFAULT 'pending'")
    op.execute("ALTER TABLE users ADD COLUMN is_admin boolean NOT NULL DEFAULT false")
    op.execute("ALTER TABLE users ADD COLUMN approved_at timestamptz")
    op.execute("ALTER TABLE users ADD COLUMN approved_by uuid REFERENCES users(id)")
    op.execute("CREATE INDEX ix_users_status ON users (status, created_at)")


def downgrade() -> None:
    op.execute("DROP INDEX ix_users_status")
    op.execute("ALTER TABLE users DROP COLUMN approved_by")
    op.execute("ALTER TABLE users DROP COLUMN approved_at")
    op.execute("ALTER TABLE users DROP COLUMN is_admin")
    op.execute("ALTER TABLE users DROP COLUMN status")
