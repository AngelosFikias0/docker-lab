from flask import Flask, jsonify
import os

app = Flask(__name__)

@app.route("/health")
def health():
    return "ok", 200

@app.route("/")
def index():
    return jsonify({
        "message": "hello from container",
        "host": os.environ.get("HOSTNAME", "unknown")
    })

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)