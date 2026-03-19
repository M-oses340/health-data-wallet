FROM python:3.10-slim
WORKDIR /app

# Install curl for healthcheck
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*

# Install anonymizer deps first (heavy — cached layer)
COPY packages/anonymizer/requirements.txt ./anonymizer-requirements.txt
RUN pip install --no-cache-dir --timeout 120 --retries 5 presidio-analyzer==2.2.354 presidio-anonymizer==2.2.354 spacy==3.7.4
RUN pip install --no-cache-dir --timeout 120 --retries 5 https://github.com/explosion/spacy-models/releases/download/en_core_web_lg-3.7.1/en_core_web_lg-3.7.1-py3-none-any.whl

# Install FL server deps
COPY packages/fl-server/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir --timeout 120 --retries 5 -r requirements.txt

# Copy source
COPY packages/fl-server/src ./src
COPY packages/fl-server/setup.py ./setup.py
COPY packages/anonymizer/src ./anonymizer_src

RUN pip install -e .

ENV PYTHONPATH=/app/anonymizer_src

EXPOSE 5001
CMD ["python3", "src/app.py"]
