FROM python:3.13-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY web.py worker.py ./
USER nobody
EXPOSE 5000
# CMD is overridden per service in docker-compose.yml
CMD ["python", "web.py"]
