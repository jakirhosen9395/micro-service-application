# syntax=docker/dockerfile:1.7
FROM python:3.14-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_ROOT_USER_ACTION=ignore \
    PYTHONPATH=/app

WORKDIR /app

RUN addgroup --system appgroup \
    && adduser --system --ingroup appgroup appuser

COPY requirements.txt ./

RUN --mount=type=cache,target=/root/.cache/pip \
    python -m pip install --upgrade pip setuptools wheel \
    && python -m pip install --prefer-binary --only-binary=:all: -r requirements.txt

COPY app ./app
COPY migrations ./migrations
COPY scripts ./scripts
COPY tests ./tests
COPY pyproject.toml ./
COPY README.md ./README.md
COPY command.sh ./command.sh

RUN chmod +x /app/command.sh \
    && chown -R appuser:appgroup /app

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/hello', timeout=3).read()"

USER appuser

CMD ["sh", "-c", "python -m app.preflight && uvicorn app.main:app --host ${AUTH_HOST:-0.0.0.0} --port ${AUTH_PORT:-8080}"]
