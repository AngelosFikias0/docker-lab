import os
import redis
from flask import Flask, jsonify, request

app = Flask(__name__)
r = redis.Redis(
    host=os.environ.get("REDIS_HOST", "redis"),
    port=6379,
    decode_responses=True,
)

@app.route("/jobs", methods=["POST"])
def enqueue():
    data = request.get_json(force=True)
    job_id = r.incr("job:counter")
    r.rpush("jobs:pending", f"{job_id}:{data.get('payload', '')}")
    return jsonify({"job_id": job_id, "status": "queued"}), 202

@app.route("/jobs")
def list_jobs():
    pending = r.lrange("jobs:pending", 0, -1)
    done    = r.lrange("jobs:done", 0, -1)
    return jsonify({"pending": len(pending), "done": len(done)})

@app.route("/health")
def health():
    r.ping()
    return jsonify({"status": "ok"})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
