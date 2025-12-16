from flask import Flask, render_template_string
import mysql.connector
import os
import time

app = Flask(__name__)

# =========================
# CONFIGURACIÓN DESDE ENV
# =========================
DB_HOST = os.getenv("DB_HOST", "db")
DB_USER = os.getenv("DB_USER", "root")
DB_PASSWORD = os.getenv("DB_PASSWORD", "root")
DB_NAME = os.getenv("DB_NAME", "holamundo")

# =========================
# ESPERA A MYSQL
# =========================
def wait_for_db():
    while True:
        try:
            conn = mysql.connector.connect(
                host=DB_HOST,
                user=DB_USER,
                password=DB_PASSWORD,
                database=DB_NAME
            )
            conn.close()
            print("✅ Conectado a MySQL")
            break
        except Exception as e:
            print("⏳ Esperando MySQL...")
            time.sleep(2)

wait_for_db()

# =========================
# TEMPLATE HTML (DISEÑO)
# =========================
HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>Hola Mundo AWS</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            background: linear-gradient(135deg, #667eea, #764ba2);
            color: #333;
            margin: 0;
            padding: 0;
        }
        .container {
            max-width: 800px;
            margin: 80px auto;
            background: white;
            border-radius: 15px;
            padding: 40px;
            box-shadow: 0 15px 30px rgba(0,0,0,0.3);
            text-align: center;
        }
        h1 {
            color: #5a67d8;
            margin-bottom: 10px;
        }
        p {
            font-size: 18px;
        }
        .info {
            margin-top: 30px;
            font-size: 16px;
            color: #555;
        }
        .badge {
            display: inline-block;
            margin-top: 15px;
            padding: 10px 20px;
            background: #48bb78;
            color: white;
            border-radius: 20px;
            font-weight: bold;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 Hola Mundo desde AWS</h1>
        <p>{{ mensaje }}</p>

        <div class="info">
            <p><b>Backend:</b> Flask + Docker</p>
            <p><b>Base de Datos:</b> MySQL</p>
            <p><b>Infraestructura:</b> EC2 + ALB + Auto Scaling</p>
            <div class="badge">Conectado correctamente</div>
        </div>
    </div>
</body>
</html>
"""

# =========================
# RUTA PRINCIPAL
# =========================
@app.route("/")
def index():
    conn = mysql.connector.connect(
        host=DB_HOST,
        user=DB_USER,
        password=DB_PASSWORD,
        database=DB_NAME
    )
    cursor = conn.cursor()
    cursor.execute("SELECT texto FROM mensajes LIMIT 1")
    mensaje = cursor.fetchone()
    cursor.close()
    conn.close()

    return render_template_string(
        HTML_TEMPLATE,
        mensaje=mensaje[0] if mensaje else "Mensaje no encontrado"
    )

# =========================
# EJECUCIÓN
# =========================
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
