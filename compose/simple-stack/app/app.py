import os
import redis
from flask import Flask, jsonify

app = Flask(__name__)
cache = redis.Redis(
    host=os.environ.get("REDIS_HOST", "redis"),
    port=6379,
    decode_responses=True,
)

@app.route("/")
def index():
    hits = cache.incr("hits")
    return jsonify({"hits": hits})

@app.route("/health")
def health():
    cache.ping()
    return jsonify({"status": "ok"})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
