
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


## 2. Bug de Producción Crítico

### ¿Cuál es el bug exacto?
No es solo que en la segunda línea del insert pongan cantidad_entrada otra vez.

El problema de fondo es este:

No se aplica el rendimiento del beneficio. el codigo registra la misma cantidad de cereza también para el pergaminoo, como si no hubiera pérdida natural en el proceso o mejor dicho la merma.

No se registra esa pérdida . No hay columna o table que diga “aquí está la merma de 15”. Por eso al sumar/restar inventarios parece que desaparecieron cantidades sin explicación.

Ya existe código para el rendimiento pero no se usa. Hay un método obtenerRendimiento() que incluso devuelve 0.85 (85 %) por defecto, pero la funcion nunca lo llama, la logica esta incompleta.

### ¿Por qué “pierdes” los 15 qq?

Porque físicamente al pasar café de cereza a pergamino siempre habra perdida, la merma no se registra, que es lo que se pierde atravez del proceso.

### ¿Qué otros datos faltan en la tabla kardex?
Falta rellenar transformacion_id esta referencia a esta tabla nos dara cuánto entro, cuánto salió, % rendimiento, merma calculada, etc.

Una columna llamada concepto para no solo depender de la columna tipo que muestre si viene de una compra, venta, transformacion, ajuste asi saber porque se movio el inventario.

#### Estructura de datos propuesta
Se debe existir la tabla llamada `transformaciones`, para que represente el proceso completo.

Esa tabla debería guardar, como mínimo:
- `id`
- `producto_entrada_id`
- `cantidad_entrada`
- `producto_salida_id`
- `cantidad_salida`
- `rendimiento`
- `merma`
- `bodega_id`
- `usuario_id`
- `fecha_entrada`
- `fecha_creacion`
- `costo_unitario_entrada`
- `costo_unitario_salida`
- `costo_total`

La tabla `kardex` debería seguir guardando los movimientos de inventario, pero cada movimiento relacionado con una transformación debería tener el mismo `transformacion_id`.

De esta forma, si se transforma café cereza a café pergamino, queda algo que diga:
```text
Transformación #123
100 qq café cereza
85 qq café pergamino
15 qq merma
85% rendimiento
```
Y en kardex quedan los movimientos vinculados a esa transformación.

### Implementa la lógica de transformación con merma/rendimiento

La lógica correcta no debería depender de un porcentaje escrito a mano en el código. Lo ideal es tener un catálogo de tipos de transformación donde se configure el rendimiento esperado por cada producto de entrada y salida.

Por ejemplo:

- Café Cereza → Café Pergamino: 85%
- Café Pergamino → Café Oro: 80%

Cuando el usuario registra una transformación, el sistema toma ese rendimiento, calcula automáticamente la cantidad de salida y la merma.

Ejemplo:

100 qq cereza × 0.85 = 85 qq pergamino  
merma = 100 - 85 = 15 qq

La transformación se guarda en una tabla `transformaciones`, y los movimientos de inventario en `kardex` quedan vinculados con `transformacion_id`.

La merma debe quedar registrada como parte del proceso para que el inventario sea auditable y no parezca que se perdieron cantidades sin explicación.