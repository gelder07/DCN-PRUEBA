
# Análisis — Prueba Técnica DNC-ERP

## Parte 1: Análisis de Código Legacy - Kardex

### 1 Identificación de problemas (performance)

#### Problemas detectados

Este codigo tiene un problema de performance causado por un patrón N+1 queries. El controlador primero consulta todos los productos activos y luego, dentro de un `foreach`, ejecuta consultas adicionales por cada producto para calcular entradas, salidas y costo promedio.

Por cada producto se ejecutan tres operaciones principales: 
Consulta del total de entradas, salidas y el movimiento de entrada para calcular el promedio.

Esto significa que el número de queries crece en función directa de la cantidad de productos. 

Los cálculos agregados de inventario deberían resolverse en una sola query no y no producto por producto.

#### Impacto en producción con 1.000 productos

- **Tiempo de respuesta alto** en la pantalla de existencias (segundos en lugar de milisegundos).
- **Saturación de MySQL** por miles de consultas pequeñas en un solo request.
- **Mayor uso de CPU y memoria en PHP** al traer y recorrer movimientos en cada producto.
- **Riesgo de timeouts** si el catálogo o el kardex siguen creciendo.
- **Mala experiencia de usuario** (pantalla lenta, especialmente en horas pico).
- **Dificultad para escalar** sin cambiar arquitectura (más usuarios = más presión sobre la misma tabla).

En el README del proyecto se indica que, con el dataset de prueba (856 productos y ~145.000 movimientos), este patrón puede tardar del orden de **~8,5 segundos** por request.

#### Estimación de queries SQL ejecutadas

Suponiendo que hay 1000 productos el métodeo ejecuta aproximadamente:

```text
1 query para consultar productos
+ 1,000 queries para sumar entradas
+ 1,000 queries para sumar salidas
+ 1,000 queries para calcular costo promedio
= 3,001 queries por request

Total = Con 1.000 productos: 1 producto + (3 funciones × 1.000) = **3.001 queries** por request.

```

### 2 Problema de negocio — costo promedio
El costo promedio también está incompleto porque calcula promedio solo de entradas históricas, pero no considera existencia actual, el problema es que no resta el efecto de las salidas,  no piensa en lo que quedó después de las salidas

Para este proyecto se deberia usar el promedio ponderado, porque FIFO es bueno si existiera inventario por lotes o fechas, o lifo no concuerda con inventario real 

La fórmula correcta recalcula el costo en cada entrada:

nuevo_costo = (existencia_anterior × costo_anterior + cantidad_entrada × precio_entrada) / (existencia_anterior + cantidad_entrada);
en salidas el costo unitario se mantiene y solo disminuye la existencia.

### 3 Refactor
Se mantiene compatibilidad con la vista porque el repositorio devuelve las mismas columna que el controlador legacy (producto_id, producto, codigo, existencia, costo, valor_total). El cambio está en cómo se calculan los datos internamente, no en la estructura que recibe la vista.