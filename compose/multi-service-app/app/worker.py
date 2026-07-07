import os
import time
import redis

r = redis.Redis(
    host=os.environ.get("REDIS_HOST", "redis"),
    port=6379,
    decode_responses=True,
)

worker_id = os.environ.get("WORKER_ID", "1")
print(f"[worker-{worker_id}] started", flush=True)

while True:
    job = r.blpop("jobs:pending", timeout=5)
    if job:
        _, payload = job
        print(f"[worker-{worker_id}] processing: {payload}", flush=True)
        time.sleep(1)
        r.rpush("jobs:done", payload)
        print(f"[worker-{worker_id}] done: {payload}", flush=True)
