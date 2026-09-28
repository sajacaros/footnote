"""track_points → walk_sessions FK

Revision ID: 0003
Revises: 0002

사용자·세션을 지워도 포인트가 남던 문제를 막는다. TimescaleDB는 hypertable에서
일반 테이블로 가는 FK를 지원한다.
"""

from alembic import op

revision = "0003"
down_revision = "0002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        "DELETE FROM track_points t "
        "WHERE NOT EXISTS (SELECT 1 FROM walk_sessions s WHERE s.id = t.session_id)"
    )
    op.execute(
        "ALTER TABLE track_points ADD CONSTRAINT fk_track_points_session "
        "FOREIGN KEY (session_id) REFERENCES walk_sessions(id) ON DELETE CASCADE"
    )


def downgrade() -> None:
    op.execute("ALTER TABLE track_points DROP CONSTRAINT fk_track_points_session")
