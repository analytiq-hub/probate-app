from alembic import op

revision = "0001_initial"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Initial empty migration; real tables will be added in later phases.
    pass


def downgrade() -> None:
    pass

