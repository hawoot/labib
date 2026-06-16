"""Central configuration.

Every value here is read from environment variables (which come from the
`.env` file in development). See `.env.example` for the full, commented list.
"""
from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # --- App ---
    app_env: str = "dev"
    secret_key: str = "dev-secret-change-me"

    # --- Database ---
    # Full override. If set, it wins (e.g. SQLite for an in-container deploy:
    # DATABASE_URL=sqlite:////home/node/apps/labib/labib.db). If empty, the URL
    # is built from the POSTGRES_* parts below (the docker-compose / VPS path).
    database_url: str = ""

    postgres_user: str = "labib"
    postgres_password: str = "labib"
    postgres_db: str = "labib"
    postgres_host: str = "db"
    postgres_port: int = 5432

    # --- File storage (uploaded documents) ---
    # Local disk in dev; swap for S3/R2 later behind the same interface.
    storage_dir: str = "./data/uploads"

    # --- LLM ("the AI brain") ---
    # provider: "openai_compatible" (OpenRouter/DeepSeek/OpenAI/Ollama/...) or "anthropic"
    llm_provider: str = "openai_compatible"
    llm_base_url: str = "https://openrouter.ai/api/v1"
    llm_api_key: str = ""
    llm_model: str = "deepseek/deepseek-chat"

    @property
    def sqlalchemy_url(self) -> str:
        if self.database_url:
            return self.database_url
        return (
            f"postgresql+psycopg://{self.postgres_user}:{self.postgres_password}"
            f"@{self.postgres_host}:{self.postgres_port}/{self.postgres_db}"
        )


@lru_cache
def get_settings() -> Settings:
    return Settings()
