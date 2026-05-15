# 🎯 Prueba Técnica Senior - DNC-ERP
## Evaluación de Expertis y Resolución de Problemas Reales

---

## 📋 Información General

**Posición:** Desarrollador Senior Full-Stack PHP  
**Duración:** 3-4 horas  
**Formato:** Análisis + Solución de Problemas Reales

---

## 🎓 Filosofía de Esta Prueba

Esta NO es una prueba típica de "crear un CRUD". Es una evaluación de tu capacidad para:

1. **Analizar código legacy existente** y entenderlo sin documentación exhaustiva
2. **Identificar y resolver problemas de producción** bajo presión
3. **Tomar decisiones arquitectónicas** justificadas
4. **Refactorizar código problemático** manteniendo compatibilidad
5. **Optimizar performance** en queries críticas
6. **Debuggear problemas complejos** de lógica de negocio

**No se proporciona:**
- ❌ Plantillas de código
- ❌ Ejemplos paso a paso
- ❌ Estructura completa de archivos

**Debes demostrar:**
- ✅ Capacidad de aprender el framework leyendo código existente
- ✅ Experiencia real resolviendo problemas de producción
- ✅ Criterio técnico para tomar decisiones
- ✅ Habilidades de debugging y análisis

---

## 🔥 PARTE 1: Análisis de Código Legacy (45 min - 25 puntos)

### Contexto

Te uniste al equipo y heredaste este controlador legacy que está causando problemas en producción:

```php
<?php
class KardexController extends ControladorBase {
    
    public function Index() {
        $Datos = new KardexFpdoModel($this->AdapterModel);
        
        // Obtener todos los productos
        $productos = $Datos->fluent()->from('productos')->fetchAll();
        
        // Para cada producto, calcular existencias
        $resultados = [];

        foreach ($productos as $producto) {
            $entradas = $Datos->fluent()
                ->from('kardex')
                ->where('producto_id = ?', $producto['id'])
                ->where('tipo = ?', 'entrada')
                ->select('SUM(cantidad) as total')
                ->fetch();
                
            $salidas = $Datos->fluent()
                ->from('kardex')
                ->where('producto_id = ?', $producto['id'])
                ->where('tipo = ?', 'salida')
                ->select('SUM(cantidad) as total')
                ->fetch();
            
            $existencia = ($entradas['total'] ?? 0) - ($salidas['total'] ?? 0);
            
            $resultados[] = [
                'producto' => $producto['nombre'],
                'existencia' => $existencia,
                'costo' => $this->calcularCostoPromedio($producto['id'])
            ];
        }
        
        $this->view('Kardex/IndexView', ['datos' => $resultados]);
    }
    
    private function calcularCostoPromedio($producto_id) {
        $Datos = new KardexFpdoModel($this->AdapterModel);
        $movimientos = $Datos->fluent()
            ->from('kardex')
            ->where('producto_id = ?', $producto_id)
            ->where('tipo = ?', 'entrada')
            ->orderBy('fecha DESC')
            ->fetchAll();
        
        $suma = 0;
        $cantidad = 0;
        foreach ($movimientos as $mov) {
            $suma += ($mov['precio_unitario'] * $mov['cantidad']);
            $cantidad += $mov['cantidad'];
        }
        
        return $cantidad > 0 ? $suma / $cantidad : 0;
    }
}
```

### 🔍 Preguntas (responde en tu documentación):

**1.1 Identificación de Problemas (10 pts)**
- Identifica TODOS los problemas de performance en este código
- Explica el impacto en producción con 1,000 productos
- Estima cuántas queries SQL se ejecutan

**1.2 Problema de Negocio (8 pts)**
- El costo promedio está mal calculado. ¿Por qué?
- ¿Qué método de costeo se debería usar? (FIFO, LIFO, Promedio Ponderado)
- Propón la fórmula correcta

**1.3 Refactorización (7 pts)**
- Escribe el código refactorizado usando PSR-4
- Reduce las queries a máximo 2 (o explica por qué necesitas más)
- Mantén compatibilidad con la vista existente

---

## 🔥 PARTE 2: Bug de Producción Crítico (60 min - 35 puntos)

### 🚨 Reporte de Bug

```
PRIORIDAD: CRÍTICA
FECHA: Hoy 3:00 AM
REPORTADO POR: Supervisor de Bodega

PROBLEMA:
Los inventarios están descuadrados. Cuando se procesa una "transformación" 
(entrada de café cereza → sale café pergamino ), las cantidades 
no coinciden.

EJEMPLO:
- Entrada: 100 qq café cereza (ID producto: 45)
- Transformación esperada: 100 qq cereza → 85 qq pergamino (ID: 67)
- Sistema registra: 100 qq cereza ENTRA (✓) pero 100 qq pergamino SALE (✗)
- Resultado: Perdemos 15 qq en el cálculo

IMPACTO:
- Inventarios irreales
- Costos mal calculados
- Auditoría en 2 días
- Cliente grande amenaza con no renovar

CÓDIGO SOSPECHOSO:
legacy/controller/TransformacionController.php - método ProcesarTransformacion()
```

### Código del Bug

```php
public function ProcesarTransformacion() {
    if (!$this->ValToken()) {
        echo json_encode(['Result' => '0']);
        return;
    }
    
    $Post = $this->RenderPost(['BtnGrabar', 'ToKen']);
    
    $producto_entrada = $Post['Val'][0];  // ID producto entrada
    $cantidad_entrada = $Post['Val'][1];  // Cantidad entrada
    $producto_salida = $Post['Val'][2];   // ID producto salida
    $bodega_id = $Post['Val'][3];
    
    // Registrar entrada
    $Datos = new KardexFpdoModel($this->AdapterModel);
    $result1 = $Datos->fluent()->insertInto('kardex', [
        'producto_id' => $producto_entrada,
        'cantidad' => $cantidad_entrada,
        'tipo' => 'entrada',
        'bodega_id' => $bodega_id,
        'fecha' => date('Y-m-d H:i:s'),
        'usuario_id' => $_SESSION['User_ID']
    ])->execute();
    
    // Registrar salida (AQUÍ ESTÁ EL BUG)
    $result2 = $Datos->fluent()->insertInto('kardex', [
        'producto_id' => $producto_salida,
        'cantidad' => $cantidad_entrada, 
        'tipo' => 'salida',
        'bodega_id' => $bodega_id,
        'fecha' => date('Y-m-d H:i:s'),
        'usuario_id' => $_SESSION['User_ID']
    ])->execute();
    
    echo json_encode([
        'Result' => ($result1 && $result2) ? '1' : '0'
    ]);
}
```

### 📝 Tu Tarea:

**2.1 Análisis del Bug (10 pts)**
- Identifica el bug exacto (no es donde crees)
- Explica POR QUÉ ocurre el problema de los 15 qq perdidos
- ¿Qué otros datos faltan en la tabla kardex?

**2.2 Solución Correcta (15 pts)**
- Propón la estructura de datos correcta
- Implementa la lógica de transformación con merma/rendimiento
- Crea el método en PSR-4 manejando:
  - Entrada de materia prima
  - Salida de producto transformado
  - Registro de merma (diferencia)
  - Cálculo de costos
  - Transacciones (rollback si falla)

**2.3 Migración de Datos (10 pts)**
- Los registros antiguos están mal. Escribe SQL para:
  - Identificar transformaciones erróneas
  - Corregir las cantidades basándote en rendimientos estándar:
    * Cereza → Pergamino: 85% rendimiento
    * Pergamino → Oro: 80% rendimiento
  - Crear registros de merma faltantes

---

## 🔥 PARTE 3: Optimización de Query Crítica (45 min - 25 puntos)

### Contexto

Este query se ejecuta en el dashboard principal (carga en cada login). Con 50 usuarios concurrentes, el servidor colapsa.

```sql
SELECT 
    p.nombre as producto,
    b.nombre as bodega,
    (
        SELECT COALESCE(SUM(cantidad), 0) 
        FROM kardex k1 
        WHERE k1.producto_id = p.id 
        AND k1.bodega_id = b.id 
        AND k1.tipo = 'entrada'
    ) - (
        SELECT COALESCE(SUM(cantidad), 0) 
        FROM kardex k2 
        WHERE k2.producto_id = p.id 
        AND k2.bodega_id = b.id 
        AND k2.tipo = 'salida'
    ) as existencia,
    (
        SELECT precio_unitario 
        FROM kardex k3 
        WHERE k3.producto_id = p.id 
        AND k3.tipo = 'entrada'
        ORDER BY fecha DESC 
        LIMIT 1
    ) as ultimo_costo
FROM productos p
CROSS JOIN bodegas b
WHERE p.estado = 1 AND b.estado = 1
ORDER BY p.nombre, b.nombre;
```

**Estadísticas:**
- productos: 856 registros
- bodegas: 12 registros
- kardex: 145,000 registros
- Tiempo actual: ~8.5 segundos
- Índices actuales: PRIMARY en cada tabla

### 📝 Tu Tarea:

**3.1 Análisis (8 pts)**
- Usa EXPLAIN para analizar el query
- Identifica el cuello de botella principal
- Calcula cuántas operaciones hace (O notation)

**3.2 Solución con Índices (7 pts)**
- Propón los índices específicos necesarios
- Justifica cada índice (no agregues índices innecesarios)
- Estima la mejora de performance

**3.3 Refactorización del Query (10 pts)**
- Reescribe el query sin subqueries correlacionadas
- Debe retornar los mismos datos
- Target: <500ms con los índices

**Bonus (+5 pts):**
- Propón una tabla materializada o caché estratégica
- Explica cuándo invalidarla

---

## 🔥 PARTE 4: Arquitectura - Decisión Técnica Real (30 min - 15 puntos)

### Situación

El gerente te pregunta: *"Necesitamos enviar 500 facturas electrónicas al SAT cada fin de mes. Actualmente el usuario hace clic en 'Generar' y espera 2-3 minutos por cada una. ¿Cómo lo resolvemos?"*

Tienes estas opciones en la mesa:

**Opción A:** Sistema de colas con Redis/RabbitMQ
**Opción B:** Cron job que procesa por lotes
**Opción C:** JavaScript que envía una por una con AJAX
**Opción D:** Procesos paralelos con PHP (pcntl_fork)

### 📝 Tu Tarea:

**4.1 Análisis de Opciones (8 pts)**
- Ventajas y desventajas de cada una
- Complejidad de implementación
- Problemas potenciales

**4.2 Recomendación (7 pts)**
- ¿Cuál elegirías y POR QUÉ?
- ¿Cómo manejas los fallos?
- ¿Cómo notificas al usuario del progreso?
- Esboza la arquitectura (código o diagrama)

---

## 🎯 BONUS: Debugging de Problema Bizarro (opcional - +10 pts)

### El Misterio

```php
// Este código funciona PERFECTO en desarrollo
// Pero falla ALEATORIAMENTE en producción
// Error: "Cannot modify header information - headers already sent"

public function exportarExcel() {
    $this->requireAuth();
    
    $datos = $this->repository->getAll();
    
    header('Content-Type: application/vnd.ms-excel');
    header('Content-Disposition: attachment; filename="reporte.xlsx"');
    
    $excel = new ExcelBuilder();
    foreach ($datos as $row) {
        $excel->addRow($row);
    }
    
    echo $excel->generate();
}
```

**Pistas:**
- En desarrollo: PHP 7.4, display_errors=On, Apache 2.4
- En producción: PHP 8.1, display_errors=Off, Nginx + PHP-FPM
- Falla ~30% de las veces
- Cuando falla, el archivo descargado está corrupto
- El error sale en el log pero no siempre

### 📝 Pregunta:
- ¿Cuál es el problema? (no es la respuesta obvia)
- ¿Cómo lo debuggearías en producción?
- ¿Cuál es la solución definitiva?

---

## 📦 Entregables

### Estructura de Entrega

```
entrega/
├── ANALISIS.md                    # Respuestas a todas las preguntas
│   ├── Parte 1: Análisis
│   ├── Parte 2: Bug Producción
│   ├── Parte 3: Optimización
│   └── Parte 4: Arquitectura
│
├── codigo/
│   ├── KardexRepository.php       # Parte 1 refactorizado
│   ├── TransformacionService.php  # Parte 2 solución
│   └── queries_optimizados.sql    # Parte 3 queries
│
├── sql/
│   ├── indices_optimizacion.sql   # Parte 3 índices
│   └── migracion_transformaciones.sql  # Parte 2 corrección datos
│
└── REFLEXION.md                   # Ver abajo
```

### ANALISIS.md
Debe incluir tus respuestas detalladas a cada pregunta con:
- Razonamiento técnico
- Justificación de decisiones
- Alternativas consideradas
- Estimaciones de impacto

### REFLEXION.md
Documento personal donde explicas:

```markdown
# Reflexión Personal

## 1. Enfoque de Análisis
¿Cómo abordaste cada problema? ¿Qué pensaste primero?

## 2. Dificultades Encontradas
¿Qué fue más desafiante? ¿Por qué?

## 3. Aprendizajes
¿Qué aprendiste del código base del ERP?

## 4. Decisiones Técnicas
¿Qué trade-offs consideraste? ¿Por qué elegiste X sobre Y?

## 5. En Producción Real
Si esto fuera tu código en producción, ¿qué harías diferente?

## 6. Preguntas para el Equipo
¿Qué te gustaría saber sobre el proyecto antes de tomar decisiones?

## 7. Tiempo Invertido
- Parte 1: X min
- Parte 2: X min  
- Parte 3: X min
- Parte 4: X min
- TOTAL: X horas
```

---

## 📊 Criterios de Evaluación

**Capacidad de Análisis (35%)**
**Expertise Técnico (35%)**
**Criterio Profesional (20%)**
**Comunicación Técnica (10%)**



## ✅ Checklist Pre-Entrega
Entregar un repositorio GitHub con commits claros

Antes de enviar, verifica:

- [ ] ANALISIS.md tiene respuestas a TODAS las preguntas
- [ ] Código compila sin errores de sintaxis
- [ ] Queries SQL son válidos
- [ ] REFLEXION.md muestra tu proceso de pensamiento
- [ ] Justificaste TODAS tus decisiones técnicas
- [ ] Consideraste casos edge
- [ ] Explicaste trade-offs
- [ ] No hay credenciales hardcodeadas
- [ ] Commits Git son descriptivos
- [ ] Todo está en la rama correcta

---
### Clarificaciones
Email: sergio@dnc.coffee
Respondemos en máximo 2 horas (horario laboral)