# syntax=docker/dockerfile:1

FROM python:3.11-slim AS builder

WORKDIR /build

COPY app/requirements.txt .

RUN pip install --no-cache-dir --prefix=/install -r requirements.txt


FROM python:3.11-slim AS runtime

RUN groupadd -r appuser \
    && useradd -r -g appuser -d /app appuser

WORKDIR /app

COPY --from=builder /install /usr/local

COPY app/ .

RUN chown -R appuser:appuser /app

USER appuser

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health')" || exit 1

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
