"""password reset tokens

Revision ID: 0005
Revises: 0004
"""

from alembic import op

revision = "0005"
down_revision = "0004"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 토큰 원문은 저장하지 않고 sha256만 둔다. DB가 새도 링크를 되살릴 수 없게 하기 위해서다.
    op.execute(
        """
        CREATE TABLE password_reset_tokens (
            id uuid PRIMARY KEY,
            user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            token_hash varchar(64) NOT NULL UNIQUE,
            expires_at timestamptz NOT NULL,
            used_at timestamptz,
            created_by uuid REFERENCES users(id) ON DELETE SET NULL,
            created_at timestamptz NOT NULL DEFAULT now()
        )
        """
    )
    op.execute("CREATE INDEX ix_password_reset_tokens_user_id ON password_reset_tokens (user_id)")


def downgrade() -> None:
    op.execute("DROP TABLE password_reset_tokens")
