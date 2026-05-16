
# Análisis — Prueba Técnica DNC-ERP

## PARTE 1: Análisis de Código Legacy - Kardex

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


## PARTE 2. Bug de Producción Crítico

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

## PARTE 3: Optimización de Query Crítica

### Análisis 

Segunla funcion EXPLAIN:

Todas las subqueries dependen de las query principal, por cada combinacion de producto y bodega vuelve a consultar kardex 

El cuello de botella principal son las subqueries correlacionadas contra kardex.

Segun el analisis usando EXPLAIN:

MySQL está leyendo:

12 bodegas
856 productos

Eso genera: 12 × 856 = 10,272 combinaciones

Subqueries:

10,272 filas × 3 subqueries = 30,816 subqueries

Cada subquery revisa aprox. 171 filas según EXPLAIN:

30,816 × 171 ≈ 5,269,536 filas revisadas

El query genera 10,272 combinaciones de producto-bodega y por cada una vuelve a consultar kardex tres veces. Aunque use idx_producto, no tiene índices compuestos que cubran producto_id, bodega_id, tipo y fecha, así que hace demasiado trabajo repetido.

### 3.2 Solución con índices

La query filtra por producto, bodega y tipo para calcular existencias. También filtra por producto, tipo y ordena por fecha descendiente para obtener el último costo.

Por eso propongo estos índices compuestos:
```sql
CREATE INDEX idx_kardex_producto_bodega_tipo
ON kardex (producto_id, bodega_id, tipo);

```

Este índice sirve para calcular existencias por producto y bodega. Permite que MySQL encuentre rápido los movimientos de un producto específico, en una bodega específica y por tipo de movimiento (entrada o salida), sin revisar todos los movimientos del producto.

```sql

CREATE INDEX idx_kardex_producto_tipo_fecha
ON kardex (producto_id, tipo, fecha DESC);

```
Este índice sirve para obtener el último costo de entrada de un producto. Como la consulta busca por producto_id, filtra tipo = 'entrada' y ordena por fecha DESC, el índice permite encontrar el último movimiento de entrada sin hacer filesort.

No agregaría muchos más índices porque cada índice adicional hace más lentas las escrituras en kardex (INSERT, UPDATE) y consume más espacio. Estos dos índices atacan directamente los filtros y ordenamientos del query crítico.

Con estos índices, el query debería pasar de revisar muchas filas repetidas en subqueries a búsquedas mucho más directas. La mejora esperada para el resultado el tiempo sera rapido y optimo

### Refactorización del query

La refactorización consiste que en lugar de calcular entradas, salidas y último costo por cada combinación producto-bodega, primero se agregan los datos de kardex y luego se unen al resultado principal.

Sin indices por 11,569 resultados tiempo de 6.279 s
Con indices por 11568 lineas tiempo de 0,782 s

## Parte 4: Arquitectura — Decisión Técnica Real

###  Análisis de Opciones 


Opción A — Sistema de colas con Redis/RabbitMQ
La idea es simple: en lugar de procesar las facturas en el momento, las metes en una lista de espera (la cola) y un proceso separado las va consumiendo una por una o en lotes.

Ventajas: el servidor web responde inmediatamente al usuario sin bloquearse, los workers pueden correr en paralelo, si una factura falla se reintenta automáticamente, y es fácil monitorear el progreso.

Desventajas: requiere instalar y mantener Redis o RabbitMQ como servicio adicional, necesitas un proceso worker corriendo permanentemente (via Supervisor o systemd), y agrega complejidad de infraestructura que puede no estar disponible en un hosting legacy.

Problemas potenciales: si el worker se cae sin Supervisor que lo levante, el proceso se detiene silenciosamente sin que nadie se entere.
Complejidad: media-alta. El concepto es simple pero la configuración de infraestructura toma tiempo.

Opción B — Cron job que procesa por lotes

Un script PHP que el servidor ejecuta automáticamente cada cierto tiempo (cada minuto, cada 5 minutos) y procesa las facturas que encuentre pendientes en base de datos.
Ventajas: extremadamente simple de implementar, no requiere instalar nada nuevo, funciona en cualquier hosting que tenga crontab, y es fácil de entender para cualquier desarrollador.

Desventajas: el procesamiento no es inmediato, depende del intervalo del cron. Si el cron tarda más que su propio intervalo, los procesos se acumulan o se pisan entre sí.
Problemas potenciales: si el script falla, nadie se entera hasta que el gerente pregunta por qué no llegaron las facturas. Tampoco puedes mostrarle al usuario un progreso en tiempo real porque el procesamiento ocurre fuera del ciclo de la aplicación.

Complejidad: baja. Es la opción más accesible.

Opción C — JavaScript enviando una por una con AJAX

El navegador del usuario hace una petición HTTP al servidor por cada factura, espera la respuesta, y pasa a la siguiente.
Ventajas: ninguna relevante para este volumen. Puede funcionar para 2 o 3 documentos.

Desventajas: 500 facturas a 2-3 minutos cada una significa entre 16 y 25 horas de procesamiento secuencial. El usuario tiene que mantener el navegador abierto todo ese tiempo. Si cierra la pestaña o pierde conexión, se pierde todo el progreso.

Problemas potenciales: el SAT probablemente rate-limitará las peticiones al detectar 500 requests seguidos desde la misma IP. El servidor mantiene 500 conexiones HTTP abiertas. Es inviable.

Complejidad: baja de implementar, pero el resultado es inaceptable en producción.

Opción D — Procesos paralelos con pcntl_fork

PHP puede crear procesos hijo que corren en paralelo usando esta función. La idea sería lanzar N procesos simultáneos, uno por grupo de facturas.
Ventajas: paralelismo real sin infraestructura externa.

Desventajas: pcntl_fork no está disponible en la mayoría de hostings compartidos ni en muchos entornos Docker sin configuración especial. Gestionar 500 procesos hijo en el mismo servidor puede agotar la memoria y CPU fácilmente. La comunicación entre procesos padre e hijo es compleja y propensa a errores.

Problemas potenciales: un memory leak en un proceso hijo puede derribar al padre. Si el servidor no tiene pcntl habilitado, el código simplemente no corre. Es una solución frágil que no pertenece en producción para este caso.

Complejidad: alta, con riesgo elevado y poca recompensa frente a las otras opciones.

###   Recomendación

Siendo honesto, no había trabajado directamente con Redis o RabbitMQ antes de esta prueba, así que me di a la tarea de investigar cada opción antes de responder.

La opción C la descarté rápido: hacer 500 requests desde el navegador uno por uno significa que el usuario espera horas, y si cierra la pestaña se pierde todo. No escala.

La opción D con pcntl_fork la descarté porque en la mayoría de entornos de producción no está habilitada, y gestionar 500 procesos hijo en el mismo servidor puede tirar el hosting completo. Es una solución frágil para este volumen.

Entre A y B la decisión fue más interesante. El cron job es simple y funciona, pero tiene un problema serio: si falla, nadie se entera hasta que el gerente pregunta por qué no llegaron las facturas. Tampoco puedes decirle al usuario cuánto falta.

El sistema de colas resuelve eso: el usuario hace clic, el servidor responde de inmediato, y un worker independiente va procesando en segundo plano. Si una factura falla, se reintenta automáticamente. 

¿Cómo manejas los fallos?

Cada factura tiene un estado en la tabla. Si el worker falla al enviar una factura al SAT, no marca como fallida de inmediato, sino que incrementa un contador de intentos. Si llega a 3 intentos fallidos, entonces sí la marca como failed y registra el error. Así el administrador puede ver exactamente qué facturas fallaron y por qué, sin perder las demás.


 ¿Cómo notificas al usuario del progreso?

El frontend hace una consulta cada pocos segundos a un endpoint que devuelve cuántas facturas van procesadas, cuántas fallaron y cuántas faltan. Con eso muestro una barra de progreso simple. No necesito WebSockets ni nada avanzado, con polling básico es suficiente para este caso. y al final puede ir viendo las facturas que fallan  o las que ya estan terminadas.

La idea central en una línea: el usuario no espera, Redis guarda la fila, y un proceso aparte va despachando.
Los 5 pasos son:

El usuario hace clic y el servidor responde al instante, sin procesar nada todavía.
PHP mete los 500 jobs en Redis, como una lista de pendientes.
Redis guarda esa lista. No procesa nada, solo la tiene lista para entregar.
Un worker PHP (proceso separado) va tomando jobs de Redis uno por uno y los procesa.
El worker llama al SAT por cada factura y guarda el resultado.

Mientras todo eso pasa en segundo plano, el usuario ve la barra avanzar. Si algo falla, el worker lo reintenta solo, sin interrumpir las demás.


