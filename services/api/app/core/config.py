from functools import lru_cache
from pydantic import BaseSettings, AnyUrl


class Settings(BaseSettings):
    database_url: AnyUrl = "postgresql+asyncpg://probate:probate@postgres:5432/probate"

    class Config:
        env_file = "/workspace/.env"
        env_file_encoding = "utf-8"
        env_prefix = ""
        case_sensitive = False


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()

