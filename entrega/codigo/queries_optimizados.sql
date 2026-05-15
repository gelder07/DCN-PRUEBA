SELECT
    p.nombre AS producto,
    b.nombre AS bodega,
    COALESCE(existencias.existencia, 0) AS existencia,
    COALESCE(ultimo_costo.precio_unitario, 0) AS ultimo_costo
FROM productos p
CROSS JOIN bodegas b
LEFT JOIN (
    SELECT
        producto_id,
        bodega_id,
        SUM(
            CASE
                WHEN tipo = 'entrada' THEN cantidad
                WHEN tipo = 'salida' THEN -cantidad
                ELSE 0
            END
        ) AS existencia
    FROM kardex
    GROUP BY producto_id, bodega_id
) existencias
    ON existencias.producto_id = p.id
    AND existencias.bodega_id = b.id
LEFT JOIN (
    SELECT
        k.producto_id,
        k.precio_unitario
    FROM kardex k
    INNER JOIN (
        SELECT
            producto_id,
            MAX(fecha) AS ultima_fecha
        FROM kardex
        WHERE tipo = 'entrada'
        GROUP BY producto_id
    ) ult
        ON ult.producto_id = k.producto_id
        AND ult.ultima_fecha = k.fecha
    WHERE k.tipo = 'entrada'
) ultimo_costo
    ON ultimo_costo.producto_id = p.id
WHERE p.estado = 1
  AND b.estado = 1
ORDER BY p.nombre, b.nombre;