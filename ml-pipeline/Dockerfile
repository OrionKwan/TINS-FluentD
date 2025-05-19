FROM python:3.9-slim

WORKDIR /app

# Copy and install requirements
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Copy the ML pipeline code
COPY . .

CMD ["python", "ml_pipeline.py"]
