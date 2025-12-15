from flask import Flask
import mysql.connector
import time

app = Flask(__name__)

# Espera a que la DB esté lista (simple y efectivo)
def wait_for_db():
    while True:
        try:
            conn = mysql.connector.connect(
                host="db",
                user="root",
                password="root",
                database="holamundo"
            )
            conn.close()
            break
        except:
            time.sleep(2)

wait_for_db()

@app.route("/")
def index():
    conn = mysql.connector.connect(
        host="db",
        user="root",
        password="root",
        database="holamundo"
    )
    cursor = conn.cursor()
    cursor.execute("SELECT texto FROM mensajes LIMIT 1")
    result = cursor.fetchone()
    cursor.close()
    conn.close()
    return result[0]

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)
