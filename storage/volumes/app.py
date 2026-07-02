import os

DATA_FILE = os.environ.get("DATA_FILE", "/data/count.txt")


def read_count():
    if not os.path.exists(DATA_FILE):
        return 0
    with open(DATA_FILE) as f:
        return int(f.read().strip() or 0)


def write_count(n):
    os.makedirs(os.path.dirname(DATA_FILE), exist_ok=True)
    with open(DATA_FILE, "w") as f:
        f.write(str(n))


count = read_count() + 1
write_count(count)
print(f"count={count}  file={DATA_FILE}")
