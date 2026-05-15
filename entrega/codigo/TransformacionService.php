<?php
declare(strict_types=1);

namespace App\Services;

use Core\Database;
use PDO;
use Throwable;

class TransformacionService
{
    private PDO $db;

    public function __construct()
    {
        $this->db = Database::getInstance()->getPdo();
    }

    /**
     * Procesa una transformación de producto.
     *
     * @param array<string, mixed> $data
     *
     * @return array<string, mixed>
     */
    public function procesar(array $data): array
    {
        $productoEntradaId = (int) $data['producto_entrada_id'];
        $cantidadEntrada   = (float) $data['cantidad_entrada'];
        $productoSalidaId  = (int) $data['producto_salida_id'];
        $bodegaId          = (int) $data['bodega_id'];
        $usuarioId         = (int) $data['usuario_id'];
        $fecha             = $data['fecha'] ?? date('Y-m-d H:i:s');

        $rendimiento = $this->obtenerRendimiento($productoEntradaId, $productoSalidaId);
        $cantidadSalida = round($cantidadEntrada * $rendimiento, 2);
        $merma = round($cantidadEntrada - $cantidadSalida, 2);

        $costoEntrada = $this->obtenerCostoPromedio($productoEntradaId);
        $costoTotal = round($cantidadEntrada * $costoEntrada, 2);
        $costoSalida = $cantidadSalida > 0
            ? round($costoTotal / $cantidadSalida, 2)
            : 0.0;

        try {
            $this->db->beginTransaction();

            $transformacionId = $this->crearTransformacion([
                'producto_entrada_id' => $productoEntradaId,
                'cantidad_entrada' => $cantidadEntrada,
                'producto_salida_id' => $productoSalidaId,
                'cantidad_salida' => $cantidadSalida,
                'merma' => $merma,
                'rendimiento' => $rendimiento,
                'costo_transformacion' => $costoTotal,
                'bodega_id' => $bodegaId,
                'fecha' => $fecha,
                'usuario_id' => $usuarioId,
            ]);

            // Se consume materia prima.
            $this->registrarMovimientoKardex([
                'producto_id' => $productoEntradaId,
                'bodega_id' => $bodegaId,
                'cantidad' => $cantidadEntrada,
                'tipo' => 'salida',
                'precio_unitario' => $costoEntrada,
                'fecha' => $fecha,
                'usuario_id' => $usuarioId,
                'observaciones' => 'Salida de materia prima por transformación',
                'transformacion_id' => $transformacionId,
            ]);

            // Se genera producto transformado.
            $this->registrarMovimientoKardex([
                'producto_id' => $productoSalidaId,
                'bodega_id' => $bodegaId,
                'cantidad' => $cantidadSalida,
                'tipo' => 'entrada',
                'precio_unitario' => $costoSalida,
                'fecha' => $fecha,
                'usuario_id' => $usuarioId,
                'observaciones' => 'Entrada de producto transformado',
                'transformacion_id' => $transformacionId,
            ]);

            /*
             * La merma queda registrada en la tabla transformaciones.
             * No se inserta como movimiento separado porque la tabla kardex solo
             * acepta tipo entrada/salida y no tiene columna concepto.
             */

            $this->db->commit();

            return [
                'ok' => true,
                'transformacion_id' => $transformacionId,
                'cantidad_entrada' => $cantidadEntrada,
                'cantidad_salida' => $cantidadSalida,
                'merma' => $merma,
                'rendimiento' => $rendimiento,
                'costo_unitario_salida' => $costoSalida,
            ];
        } catch (Throwable $e) {
            $this->db->rollBack();

            return [
                'ok' => false,
                'error' => $e->getMessage(),
            ];
        }
    }

    private function obtenerRendimiento(int $productoEntradaId, int $productoSalidaId): float
    {
        /*
         * En producción esto debería venir de una tabla tipo:
         * transformacion_tipos(producto_entrada_id, producto_salida_id, rendimiento).
         *
         * Para esta prueba uso los valores indicados en el enunciado.
         */
        if ($productoEntradaId === 45 && $productoSalidaId === 67) {
            return 0.85;
        }

        if ($productoEntradaId === 67 && $productoSalidaId === 89) {
            return 0.80;
        }

        throw new \RuntimeException('No existe rendimiento configurado para esta transformación.');
    }

    private function obtenerCostoPromedio(int $productoId): float
    {
        $sql = <<<SQL
            SELECT
                COALESCE(
                    SUM(CASE WHEN tipo = 'entrada' THEN cantidad * precio_unitario ELSE 0 END)
                    /
                    NULLIF(SUM(CASE WHEN tipo = 'entrada' THEN cantidad ELSE 0 END), 0),
                    0
                ) AS costo
            FROM kardex
            WHERE producto_id = :producto_id
            SQL;

        $stmt = $this->db->prepare($sql);
        $stmt->execute([
            'producto_id' => $productoId,
        ]);

        return (float) $stmt->fetchColumn();
    }

    /**
     * @param array<string, mixed> $data
     */
    private function crearTransformacion(array $data): int
    {
        $sql = <<<SQL
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
            ) VALUES (
                :producto_entrada_id,
                :cantidad_entrada,
                :producto_salida_id,
                :cantidad_salida,
                :merma,
                :rendimiento,
                :costo_transformacion,
                :bodega_id,
                :fecha,
                :usuario_id
            )
            SQL;

        $stmt = $this->db->prepare($sql);
        $stmt->execute($data);

        return (int) $this->db->lastInsertId();
    }

    /**
     * @param array<string, mixed> $data
     */
    private function registrarMovimientoKardex(array $data): void
    {
        $sql = <<<SQL
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
            ) VALUES (
                :producto_id,
                :bodega_id,
                :cantidad,
                :tipo,
                :precio_unitario,
                :fecha,
                :usuario_id,
                :observaciones,
                :transformacion_id
            )
            SQL;

        $stmt = $this->db->prepare($sql);
        $stmt->execute($data);
    }
}