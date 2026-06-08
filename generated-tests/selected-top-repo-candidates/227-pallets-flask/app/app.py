# Generated from immutable public Flask README evidence.
from flask import Flask

app = Flask(__name__)

@app.route("/")
def hello():
    return "Hello, World!"