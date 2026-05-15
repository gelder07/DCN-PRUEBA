CREATE INDEX idx_kardex_producto_bodega_tipo
ON kardex (producto_id, bodega_id, tipo);


CREATE INDEX idx_kardex_producto_tipo_fecha
ON kardex (producto_id, tipo, fecha DESC);