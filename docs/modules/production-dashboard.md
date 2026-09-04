# Panel de fabricacion

## Objetivo

El panel ofrece una vista global y de solo lectura del estado de todas las
lineas MES activas. Está dirigido a responsables de fabricación y no sustituye
la mesa táctil del operario.

La ruta del piloto es /dashboard y el contrato HTTP es:

GET /api/production-dashboard

## Datos autoritativos

Cada instantánea incluye la hora UTC del servidor y todas las líneas activas,
incluidas las que están LIBRE. Para una línea con sesión activa reutiliza la
misma lectura prod.obtener_estado_mesa que consume el terminal:

- estado efectivo de línea y mesa;
- orden, artículo, descripción y lote;
- cantidad buena, objetivo, reserva activa y scrap;
- tiempo productivo y capacidad teórica actual;
- personas con fichaje abierto, estado y tiempo individual;
- formato POK y unidades por palé;
- número de palés cerrados;
- estado más reciente de salida NAV y etiqueta;
- cantidades pendientes o con incidencia en NAV e impresión.

El frontend no reconstruye reglas productivas. Solo proyecta los valores
persistidos que devuelve el backend; los cronómetros avanzan localmente entre
instantáneas con la misma regla de la mesa.

## Actualización y fallos

La pantalla solicita una instantánea cada cinco segundos. Las consultas son de
solo lectura y no contactan NAV, RFID ni impresoras.

Si falla un refresco, se conserva la última instantánea visible y el panel se
marca como desconectado. No se sustituyen los datos por ceros ni se ocultan las
líneas. Una nueva lectura correcta retira el aviso.

RESULTADO_DESCONOCIDO se presenta como reconciliación pendiente mientras el
Worker sigue dentro de su contrato. Solo ERROR_DEFINITIVO, una impresión en
ERROR o una línea BLOQUEADA elevan el contador de atención.

## Alcance inicial

El panel es informativo: no inicia mesas, no ficha personas, no cierra palés,
no reimprime y no finaliza órdenes. Las acciones operativas permanecen en el
terminal de producción y conservan sus controles de RFID y supervisor.
