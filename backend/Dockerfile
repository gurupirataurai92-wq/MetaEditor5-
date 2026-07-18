FROM python:3.12-slim AS runtime

WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt psycopg2-binary

COPY app ./app

EXPOSE 8000
# Twelve-factor: all configuration (SIMS_DATABASE_URL, SIMS_JWT_SECRET, …)
# comes from the environment.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
