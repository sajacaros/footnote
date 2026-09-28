"""initial schema

Revision ID: 0001
Revises:
"""

from alembic import op

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("CREATE EXTENSION IF NOT EXISTS timescaledb")
    op.execute("CREATE EXTENSION IF NOT EXISTS postgis")

    op.execute(
        """
        CREATE TABLE users (
            id uuid PRIMARY KEY,
            email varchar(320) NOT NULL UNIQUE,
            password_hash text NOT NULL,
            display_name varchar(100) NOT NULL,
            created_at timestamptz NOT NULL DEFAULT now()
        )
        """
    )
    op.execute(
        """
        CREATE TABLE refresh_tokens (
            jti uuid PRIMARY KEY,
            user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            expires_at timestamptz NOT NULL,
            revoked_at timestamptz
        )
        """
    )
    op.execute("CREATE INDEX ix_refresh_tokens_user_id ON refresh_tokens (user_id)")

    op.execute(
        """
        CREATE TABLE walk_sessions (
            id uuid PRIMARY KEY,
            user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            title varchar(200) NOT NULL,
            note text,
            started_at timestamptz NOT NULL,
            ended_at timestamptz,
            featured_photo_id uuid,
            route geometry(LineString, 4326),
            distance_m double precision,
            point_count integer NOT NULL DEFAULT 0,
            created_at timestamptz NOT NULL DEFAULT now(),
            updated_at timestamptz NOT NULL DEFAULT now(),
            deleted_at timestamptz
        )
        """
    )
    op.execute(
        "CREATE INDEX ix_walk_sessions_user_started ON walk_sessions (user_id, started_at DESC)"
    )
    op.execute("CREATE INDEX ix_walk_sessions_route ON walk_sessions USING gist (route)")

    # 세션 하나의 포인트를 통째로 읽는 조회가 대부분이라 session_id로 묶어 압축한다.
    op.execute(
        """
        CREATE TABLE track_points (
            session_id uuid NOT NULL,
            seq integer NOT NULL,
            recorded_at timestamptz NOT NULL,
            lat double precision NOT NULL,
            lng double precision NOT NULL,
            elevation double precision,
            accuracy double precision,
            speed double precision,
            PRIMARY KEY (session_id, seq, recorded_at)
        )
        """
    )
    op.execute(
        "SELECT create_hypertable('track_points', by_range('recorded_at', INTERVAL '7 days'))"
    )
    op.execute(
        """
        ALTER TABLE track_points SET (
            timescaledb.compress,
            timescaledb.compress_segmentby = 'session_id',
            timescaledb.compress_orderby = 'seq'
        )
        """
    )
    op.execute("SELECT add_compression_policy('track_points', INTERVAL '30 days')")

    op.execute(
        """
        CREATE TABLE walk_photos (
            id uuid PRIMARY KEY,
            session_id uuid NOT NULL REFERENCES walk_sessions(id) ON DELETE CASCADE,
            user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            taken_at timestamptz NOT NULL,
            lat double precision NOT NULL,
            lng double precision NOT NULL,
            caption text,
            sha256 varchar(64) NOT NULL,
            size_bytes bigint NOT NULL,
            content_type varchar(50) NOT NULL,
            status varchar(20) NOT NULL DEFAULT 'pending',
            created_at timestamptz NOT NULL DEFAULT now(),
            completed_at timestamptz,
            deleted_at timestamptz
        )
        """
    )
    op.execute("CREATE INDEX ix_walk_photos_session_id ON walk_photos (session_id)")
    op.execute("CREATE INDEX ix_walk_photos_user_id ON walk_photos (user_id)")


def downgrade() -> None:
    op.execute("DROP TABLE walk_photos")
    op.execute("DROP TABLE track_points")
    op.execute("DROP TABLE walk_sessions")
    op.execute("DROP TABLE refresh_tokens")
    op.execute("DROP TABLE users")
