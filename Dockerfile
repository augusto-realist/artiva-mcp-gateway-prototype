FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY src/ src/
COPY run.py .

# Cloud Run injects PORT at runtime; src/config.py reads it automatically.
EXPOSE 8080

CMD ["python3", "run.py"]
