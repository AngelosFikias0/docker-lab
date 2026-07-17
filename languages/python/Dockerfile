# Interpreted: no compile step. Runtime ships inside the image.
# Layer ordering: dependencies before source — pip install cached separately from app code.
FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install -r requirements.txt

COPY app.py .

EXPOSE 8080
CMD ["python", "app.py"]
