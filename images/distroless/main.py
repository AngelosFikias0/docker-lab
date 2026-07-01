from flask import Flask, jsonify
import os

app = Flask(__name__)

@app.route("/health")
def health():
    return "ok", 200

@app.route("/")
def index():
    return jsonify({
        "message": "hello from distroless",
        "host": os.environ.get("HOSTNAME", "unknown")
    })
