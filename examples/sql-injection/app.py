from flask import Flask, request, jsonify
import sqlite3

app = Flask(__name__)

def init_db():
    conn = sqlite3.connect("users.db")
    conn.execute("CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, username TEXT, password TEXT, role TEXT)")
    conn.execute("INSERT OR IGNORE INTO users VALUES (1, 'admin', 's3cr3tP@ss!', 'admin')")
    conn.execute("INSERT OR IGNORE INTO users VALUES (2, 'user', 'password123', 'user')")
    conn.commit()
    conn.close()

@app.route("/login", methods=["POST"])
def login():
    username = request.form.get("username", "")
    password = request.form.get("password", "")

    conn = sqlite3.connect("users.db")
    query = f"SELECT * FROM users WHERE username = '{username}' AND password = '{password}'"
    cursor = conn.execute(query)
    user = cursor.fetchone()
    conn.close()

    if user:
        return jsonify({"status": "ok", "user": user[1], "role": user[3]})
    return jsonify({"status": "error", "message": "Invalid credentials"}), 401

if __name__ == "__main__":
    init_db()
    app.run(host="0.0.0.0", port=5000)
