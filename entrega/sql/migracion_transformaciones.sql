-- ============================================================================
-- Parte 2.3 - Migración de transformaciones con cantidades incorrectas
-- ============================================================================
--
-- Objetivo:
-- 1. Identificar transformaciones antiguas con el bug.
-- 2. Corregir cantidad de producto transformado usando rendimiento estándar.
-- 3. Crear registro de transformación.
-- 4. Crear movimiento de merma faltante.
--
-- Rendimientos del enunciado:
-- - Café Cereza (45)    -> Café Pergamino (67): 85%
-- - Café Pergamino (67) -> Café Oro (89):       80%
--
-- Nota:
-- La tabla kardex solo permite tipo = 'entrada' o 'salida'. Por eso la merma
-- se registra como una salida del producto de entrada, con observación clara.
-- En producción haría backup antes de ejecutar esto.
-- ============================================================================

USE dnc_erp_test;

-- 1) Crear tabla de cabecera si todavía no existe.
-- Esto queda fuera de la transacción porque MySQL hace commit implícito en DDL.
CREATE TABLE IF NOT EXISTS transformaciones (
    id INT AUTO_INCREMENT PRIMARY KEY,
    producto_entrada_id INT NOT NULL,
    cantidad_entrada DECIMAL(10,2) NOT NULL,
    producto_salida_id INT NOT NULL,
    cantidad_salida DECIMAL(10,2) NOT NULL,
    merma DECIMAL(10,2) NOT NULL COMMENT 'Diferencia por pérdida natural',
    rendimiento DECIMAL(5,2) NOT NULL COMMENT 'Porcentaje de rendimiento',
    costo_transformacion DECIMAL(10,2) DEFAULT 0,
    bodega_id INT NOT NULL,
    fecha DATETIME NOT NULL,
    usuario_id INT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (producto_entrada_id) REFERENCES productos(id),
    FOREIGN KEY (producto_salida_id) REFERENCES productos(id),
    FOREIGN KEY (bodega_id) REFERENCES bodegas(id),
    FOREIGN KEY (usuario_id) REFERENCES seg_usuario(id),

    INDEX idx_fecha (fecha),
    INDEX idx_productos (producto_entrada_id, producto_salida_id)
) ENGINE=InnoDB
COMMENT='Registro de transformaciones de productos';

START TRANSACTION;

-- 2) Identificar movimientos sospechosos.
-- Buscamos pares donde la cantidad de entrada y salida son iguales,
-- que es justamente el bug: no se aplicó rendimiento.
DROP TEMPORARY TABLE IF EXISTS tmp_transformaciones_erroneas;

CREATE TEMPORARY TABLE tmp_transformaciones_erroneas AS
SELECT
    k_in.id AS kardex_entrada_id,
    k_out.id AS kardex_salida_id,
    k_in.producto_id AS producto_entrada_id,
    k_out.producto_id AS producto_salida_id,
    k_in.bodega_id,
    k_in.usuario_id,
    k_in.fecha AS fecha_entrada,
    k_out.fecha AS fecha_salida,
    k_in.cantidad AS cantidad_entrada,
    CASE
        WHEN k_in.producto_id = 45 AND k_out.producto_id = 67 THEN 0.85
        WHEN k_in.producto_id = 67 AND k_out.producto_id = 89 THEN 0.80
    END AS rendimiento,
    ROUND(
        k_in.cantidad *
        CASE
            WHEN k_in.producto_id = 45 AND k_out.producto_id = 67 THEN 0.85
            WHEN k_in.producto_id = 67 AND k_out.producto_id = 89 THEN 0.80
        END,
        2
    ) AS cantidad_salida_correcta,
    ROUND(
        k_in.cantidad -
        (
            k_in.cantidad *
            CASE
                WHEN k_in.producto_id = 45 AND k_out.producto_id = 67 THEN 0.85
                WHEN k_in.producto_id = 67 AND k_out.producto_id = 89 THEN 0.80
            END
        ),
        2
    ) AS merma,
    ROUND(k_in.cantidad * k_in.precio_unitario, 2) AS costo_transformacion
FROM kardex k_in
INNER JOIN kardex k_out
    ON k_out.bodega_id = k_in.bodega_id
    AND k_out.usuario_id = k_in.usuario_id
    AND k_out.cantidad = k_in.cantidad
    AND k_out.transformacion_id IS NULL
WHERE k_in.transformacion_id IS NULL
  AND k_in.tipo = 'entrada'
  AND k_out.tipo = 'salida'
  AND (
      (k_in.producto_id = 45 AND k_out.producto_id = 67)
      OR
      (k_in.producto_id = 67 AND k_out.producto_id = 89)
  )
  -- En los datos de prueba los registros bug están marcados así.
  AND k_out.observaciones LIKE '%BUG%'
  -- Misma operación o días cercanos, como los ejemplos del dataset.
  AND ABS(TIMESTAMPDIFF(DAY, k_in.fecha, k_out.fecha)) <= 2;

-- Auditoría previa: revisar esto antes de confirmar en producción.
SELECT
    kardex_entrada_id,
    kardex_salida_id,
    producto_entrada_id,
    producto_salida_id,
    cantidad_entrada,
    rendimiento,
    cantidad_salida_correcta,
    merma
FROM tmp_transformaciones_erroneas
ORDER BY fecha_salida;

-- 3) Crear cabeceras de transformación.
INSERT INTO transformaciones (
    producto_entrada_id,
    cantidad_entrada,
    producto_salida_id,
    cantidad_salida,
    merma,
    rendimiento,
    costo_transformacion,
    bodega_id,
    fecha,
    usuario_id
)
SELECT
    producto_entrada_id,
    cantidad_entrada,
    producto_salida_id,
    cantidad_salida_correcta,
    merma,
    rendimiento,
    costo_transformacion,
    bodega_id,
    fecha_salida,
    usuario_id
FROM tmp_transformaciones_erroneas;

-- 4) Enlazar los movimientos originales a su transformación.
UPDATE kardex k
INNER JOIN tmp_transformaciones_erroneas tmp
    ON k.id IN (tmp.kardex_entrada_id, tmp.kardex_salida_id)
INNER JOIN transformaciones t
    ON t.producto_entrada_id = tmp.producto_entrada_id
    AND t.producto_salida_id = tmp.producto_salida_id
    AND t.cantidad_entrada = tmp.cantidad_entrada
    AND t.cantidad_salida = tmp.cantidad_salida_correcta
    AND t.merma = tmp.merma
    AND t.bodega_id = tmp.bodega_id
    AND t.fecha = tmp.fecha_salida
    AND t.usuario_id = tmp.usuario_id
SET k.transformacion_id = t.id;

-- 5) Corregir la cantidad del producto transformado.
-- Ejemplo: 100 pergamino -> 85 pergamino.
UPDATE kardex k_out
INNER JOIN tmp_transformaciones_erroneas tmp
    ON tmp.kardex_salida_id = k_out.id
SET
    k_out.cantidad = tmp.cantidad_salida_correcta,
    k_out.observaciones = CONCAT(
        COALESCE(k_out.observaciones, ''),
        ' | Cantidad corregida por rendimiento estándar'
    );

-- 6) Crear el movimiento de merma faltante.
-- Por limitación del ENUM se registra como salida del producto de entrada.
INSERT INTO kardex (
    producto_id,
    bodega_id,
    cantidad,
    tipo,
    precio_unitario,
    fecha,
    usuario_id,
    observaciones,
    transformacion_id
)
SELECT
    tmp.producto_entrada_id,
    tmp.bodega_id,
    tmp.merma,
    'salida',
    k_in.precio_unitario,
    tmp.fecha_salida,
    tmp.usuario_id,
    CONCAT(
        'Merma por transformación ',
        tmp.producto_entrada_id,
        ' -> ',
        tmp.producto_salida_id,
        ' (rendimiento ',
        ROUND(tmp.rendimiento * 100, 2),
        '%)'
    ),
    t.id
FROM tmp_transformaciones_erroneas tmp
INNER JOIN kardex k_in
    ON k_in.id = tmp.kardex_entrada_id
INNER JOIN transformaciones t
    ON t.producto_entrada_id = tmp.producto_entrada_id
    AND t.producto_salida_id = tmp.producto_salida_id
    AND t.cantidad_entrada = tmp.cantidad_entrada
    AND t.cantidad_salida = tmp.cantidad_salida_correcta
    AND t.merma = tmp.merma
    AND t.bodega_id = tmp.bodega_id
    AND t.fecha = tmp.fecha_salida
    AND t.usuario_id = tmp.usuario_id
WHERE tmp.merma > 0;

-- 7) Verificación posterior.
SELECT
    t.id AS transformacion_id,
    pe.nombre AS producto_entrada,
    t.cantidad_entrada,
    ps.nombre AS producto_salida,
    t.cantidad_salida,
    t.merma,
    CONCAT(ROUND(t.rendimiento * 100, 2), '%') AS rendimiento,
    t.fecha
FROM transformaciones t
INNER JOIN productos pe ON pe.id = t.producto_entrada_id
INNER JOIN productos ps ON ps.id = t.producto_salida_id
ORDER BY t.id DESC;

COMMIT;

-- Si al revisar la auditoría previa algo no cuadra, reemplazar COMMIT por ROLLBACK.
