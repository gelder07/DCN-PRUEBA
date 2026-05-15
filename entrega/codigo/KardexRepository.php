<?php
declare(strict_types=1);

namespace App\Models\Repository;

use Core\Model;


class KardexRepository extends Model
{
    protected string $table = 'kardex';

    /**
     * @return array<int, array<string, mixed>>
     */
    public function obtenerResumenExistencias(): array
    {
        $productos = $this->obtenerProductosActivos();
        $movimientos = $this->obtenerMovimientosOrdenados();

        $resumen = [];

        foreach ($productos as $producto) {
            $id = (int) $producto['id'];
            $resumen[$id] = [
                'producto_id'   => $id,
                'producto'      => $producto['nombre'],
                'codigo'        => $producto['codigo'],
                'existencia'    => 0.0,
                'costo'         => 0.0,
                'valor_total'   => 0.0,
            ];
        }

        foreach ($movimientos as $mov) {
            $id = (int) $mov['producto_id'];
            if (!isset($resumen[$id])) {
                continue;
            }

            $cantidad = (float) $mov['cantidad'];
            $precio   = (float) $mov['precio_unitario'];

            if ($mov['tipo'] === 'entrada') {
                $this->aplicarEntrada($resumen[$id], $cantidad, $precio);
            } elseif ($mov['tipo'] === 'salida') {
                $this->aplicarSalida($resumen[$id], $cantidad);
            }
        }

        foreach ($resumen as &$fila) {
            $fila['existencia']  = round($fila['existencia'], 2);
            $fila['costo']       = round($fila['costo'], 2);
            $fila['valor_total'] = round($fila['existencia'] * $fila['costo'], 2);
        }
        
        unset($fila);

        return array_values($resumen);
    }

    /**
     * Entrada: recalcula costo con lo que hay + lo que entra.
     */
    private function aplicarEntrada(array &$fila, float $cantidad, float $precio): void
    {
        $existencia = $fila['existencia'];
        $costo      = $fila['costo'];

        if ($existencia + $cantidad <= 0) {
            $fila['costo'] = $precio;
        } else {
            $valorAnterior = $existencia * $costo;
            $valorEntrada  = $cantidad * $precio;
            $fila['costo'] = ($valorAnterior + $valorEntrada) / ($existencia + $cantidad);
        }

        $fila['existencia'] += $cantidad;
    }

    /**
     * Salida: solo baja existencia; el costo unitario no cambia.
     */
    private function aplicarSalida(array &$fila, float $cantidad): void
    {
        $fila['existencia'] -= $cantidad;
    }

    private function obtenerProductosActivos(): array
    {
        $sql = <<<SQL
            SELECT id, nombre, codigo
            FROM productos
            WHERE estado = 1
            ORDER BY nombre ASC
            SQL;

        $query = $this->query()->prepare($sql);
        $query->execute();

        return $query->fetchAll();
    }

    private function obtenerMovimientosOrdenados(): array
    {
        $sql = <<<SQL
            SELECT
                k.producto_id,
                k.tipo,
                k.cantidad,
                k.precio_unitario
            FROM kardex k
            INNER JOIN productos p ON p.id = k.producto_id AND p.estado = 1
            ORDER BY k.producto_id ASC, k.fecha ASC, k.id ASC
            SQL;

        $query = $this->query()->prepare($sql);
        $query->execute();

        return $query->fetchAll();
    }
}