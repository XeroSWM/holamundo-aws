CREATE TABLE IF NOT EXISTS mensajes (
  id INT AUTO_INCREMENT PRIMARY KEY,
  texto VARCHAR(100) NOT NULL
);

INSERT INTO mensajes (texto)
VALUES ('Hola mundo desde la base de datos');
