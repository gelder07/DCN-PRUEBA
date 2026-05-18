# Reflexión Personal

## 1. Enfoque de Análisis

Mi primer paso fue leer todo el enunciado de principio a fin antes de tocar una sola
línea de código. Quería entender el sistema completo antes de opinar sobre cualquier
parte.

Luego revisé cada bloque de código legacy que ya existía: el KardexController, el
TransformacionController, y el esquema de la base de datos. Por último restauré la
base de datos con los datos de prueba para terminar de comprender el ecosistema real
del sistema, cómo fluyen los datos y qué impacto tiene cada movimiento en el kardex.

Ese orden me permitió llegar a cada parte de la prueba con contexto, y no solo
reaccionar ante el código en frío.

## 2. Dificultades Encontradas

Lo que más tiempo y esfuerzo me tomó fue construir el script de migración de las transformaciones,
 No era solo escribir SQL, sino resolver varios
problemas encadenados:

- Primero identificar los registros erróneos sin tener una columna que los marcara
  claramente, usando lógica de cruce entre entradas y salidas con cantidades iguales.
- Luego respetar la limitación de MySQL: `CREATE TABLE` hace commit implícito, así
  que la creación de la tabla no puede estar dentro de la transacción.
- Después construir la tabla temporal para auditoría antes de tocar datos reales,
  para poder revisar qué se va a corregir antes de confirmar.
- Y finalmente encadenar correctamente los pasos: crear la cabecera en
  `transformaciones`, enlazar los movimientos originales, corregir la cantidad del
  producto transformado, e insertar el movimiento de merma faltante, todo en el
  orden correcto para que las claves foráneas no fallen.

Ese script resume bien el desafío de trabajar con datos históricos corruptos: no
puedes simplemente borrar y volver a insertar, tienes que corregir quirúrgicamente
sin romper la trazabilidad.

## 3. Aprendizajes

Dos cosas me marcaron especialmente:

**El código legacy tiene lógica real de negocio que no se puede cambiar a lo loco.**
Aunque el código parezca viejo o sin estructura, puede contener reglas de negocio
críticas. Antes de refactorizar hay que entender qué hace y por qué existe así.

**Los errores en PHP pueden tener causas completamente invisibles**, como el BOM
(Byte Order Mark), un carácter que ningún editor muestra pero que rompe los headers
HTTP. Eso me recordó que en producción los problemas intermitentes suelen venir de
causas silenciosas, no de errores evidentes.

## 4. Decisiones Técnicas

**Kardex - Promedio Ponderado Móvil vs. costo histórico SQL:**
Elegí calcular el costo en PHP con dos queries en lugar de un solo query SQL que
devolviera un promedio histórico total. La razón es que el promedio histórico no
refleja la realidad: lo que importa es qué cuesta vender lo que tienes *ahora*, no
lo que costó en promedio desde el inicio. El promedio ponderado móvil recalcula el
costo cada vez que entra stock nuevo, que es lo que corresponde en un sistema ERP real.

**Arquitectura - Redis (Message Queue) sobre Cron Job y AJAX:**
Para el envío masivo de 500 facturas electrónicas elegí una cola de mensajes con
Redis porque garantiza que cada factura se procese exactamente una vez, incluso si
el servidor reinicia. El AJAX no garantiza que el proceso termine si el usuario
cierra el navegador. El Cron Job es más simple pero no escala bien si el volumen
crece. Redis permite reintentos automáticos y trazabilidad de cada mensaje sin
depender de que el usuario espere.

## 5. En Producción Real

Haría las tres cosas siguientes antes de desplegar cualquiera de los cambios:

1. **Tests automáticos o manuales** 
2. **Conversación con el equipo de trabajo** 
3. **Backup completo antes de cualquier migración de datos**
4. **Definir un plan de rollback antes de entrar.**
5. **Crear una tabla donde de logs donde se guarden todos los errores.**
6. **Unas tablas para el tema de auditoria donde se guarden todos los cambios el crud completo de que pasa en cada tabla.**
7. **Un envio de correos por cada errores que este pasando de los endpoints**


## 6. Preguntas para el Equipo

Antes de tomar decisiones en este proyecto preguntaría:

- **¿Qué herramientas de monitoreo y logs usan en producción?** Necesito saber
  si hay visibilidad sobre errores y performance antes de desplegar cambios.
- **¿Cuál es el plan a largo plazo para el código legacy?** ¿Se está migrando
  gradualmente o se va a mantener así? Eso cambia la profundidad de refactoring
  que tiene sentido hacer hoy.
- **¿Hay tests automáticos o todo se prueba manualmente?** Si no hay tests,
  cualquier cambio al kardex o a las transformaciones es de alto riesgo.
- **¿Qué versión de PHP y MySQL están usando en producción?** No es lo mismo
  optimizar para MySQL 5.7 que para 8.0, y algunas soluciones como `ROW_NUMBER()`
  solo existen en la versión nueva.- 
  **¿En qué servidor corre la aplicación?** Apache o Nginx cambia cómo se comporta
  el output buffering de PHP, que fue exactamente la causa del bug de headers en el Bonus.
- **¿Qué librerías o dependencias existen?** Para saber
  qué puedo usar sin añadir peso al proyecto y qué ya está disponible.



## 7. Tiempo Invertido

- Parte 1 (Kardex Legacy): ~50 min
- Parte 2 (Bug Transformación): ~1 hora
- Parte 3 (Optimización SQL): ~40 min
- Parte 4 + Bonus (Arquitectura y Debugging): ~30 min