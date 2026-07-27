import os

BASE_DIR = os.path.abspath(os.path.dirname(__file__))


class Config:
    """Application configuration.

    Values can be overridden with environment variables so the same code runs
    in development and production without edits.
    """

    SECRET_KEY = os.environ.get("SECRET_KEY", "dev-secret-change-me")
    SQLALCHEMY_DATABASE_URI = os.environ.get(
        "DATABASE_URL", "sqlite:///" + os.path.join(BASE_DIR, "school.db")
    )
    SQLALCHEMY_TRACK_MODIFICATIONS = False
