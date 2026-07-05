import os

# Reads secret from a mounted file — preferred over env var.
# /run/secrets/ is the conventional mount path for Docker/Compose secrets.
secret_file = "/run/secrets/api_key"
env_secret  = os.environ.get("API_KEY", "")

if os.path.exists(secret_file):
    with open(secret_file) as f:
        print(f"Secret from file: {f.read().strip()[:4]}****")
elif env_secret:
    print(f"Secret from env:  {env_secret[:4]}****")
else:
    print("No secret found")
