FROM python:3.13-slim

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1

RUN apt-get update && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY infra/streamlit/requirements-streamlit.txt /requirements-streamlit.txt
RUN pip install --no-input --no-cache-dir -r /requirements-streamlit.txt

COPY streamlit_app.py ./streamlit_app.py
COPY lib ./lib
COPY pyproject.toml ./pyproject.toml

ENV PYTHONPATH=/app

EXPOSE 8501

CMD ["streamlit", "run", "streamlit_app.py", "--server.address=0.0.0.0", "--server.port=8501"]