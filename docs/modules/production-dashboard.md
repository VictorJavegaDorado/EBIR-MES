# Panel de fabricacion

## Objetivo

El panel ofrece una vista global y de solo lectura del estado de las lineas
MES activas. Está dirigido a jefes de línea y responsables de fabricación y no
sustituye la mesa táctil del operario.

La ruta del piloto es /dashboard y los contratos HTTP son:

GET /api/production-dashboard?supervisor=<codigo NAV del jefe>
GET /api/production-dashboard/supervisors

## Vista por jefe de linea y vista de planta

La planta real tendrá unas veinte líneas repartidas entre varios jefes de
línea, cada uno con una pantalla situada entre sus 4-5 líneas. Por eso el panel
tiene dos vistas:

- **Vista por jefe**: `?supervisor=<codigo>` devuelve solo las líneas con
  asignación vigente a ese jefe y el propio jefe (`supervisor`). La pantalla
  fija el jefe en la URL (`/dashboard?jefe=<codigo>`), de modo que cada
  pantalla física abre la suya en modo quiosco. Con 1-4 líneas se usa una
  rejilla 2×2, con 5-6 una 3×2 y con 7-8 una variante compacta 4×2.
- **Vista de planta**: sin filtro y con más de seis líneas se muestran
  tarjetas mínimas (estado, orden, avance, cumplimiento y jefe asignado) en
  cinco columnas. Con seis líneas o menos se mantienen las tarjetas completas.

El selector del resumen superior permite cambiar de jefe o volver a toda la
planta; la lista procede de `/supervisors`, que solo incluye supervisores
activos con rol vigente y líneas asignadas.

La asignación jefe ↔ línea vive en `cfg.lineas_jefes` (paquete
`database/049A_asignacion_jefes_linea.sql`): una línea tiene como máximo un
jefe vigente y la vigencia se cierra sin borrar historial. Mientras el paquete
no esté instalado, el panel funciona sin filtro y la lista de jefes queda
vacía. El reparto real se entrega como paquete de datos, igual que el resto de
maestros; no existe pantalla de administración.

## Datos autoritativos

Cada instantánea incluye la hora UTC del servidor y las líneas visibles,
incluidas las que están LIBRE. Para una línea con sesión activa reutiliza la
misma lectura prod.obtener_estado_mesa que consume el terminal:

- estado efectivo de línea y mesa;
- orden, artículo, descripción y lote;
- cantidad buena, objetivo, reserva activa y scrap;
- tiempo productivo y capacidad teórica actual;
- unidades teóricas acumuladas (`theoreticalUnitsToDate`) y segundos-recurso
  (`resourceSeconds`), ambos calculados sobre los tramos de capacidad de la
  sesión con el mismo criterio que la mesa;
- personas con fichaje abierto, estado y tiempo individual;
- formato POK y unidades por palé;
- número de palés cerrados;
- estado más reciente de salida NAV y etiqueta;
- cantidades pendientes o con incidencia en NAV e impresión;
- jefe de línea asignado (código NAV y nombre), si existe.

El frontend no reconstruye reglas productivas. Solo proyecta los valores
persistidos que devuelve el backend; los cronómetros avanzan localmente entre
instantáneas con la misma regla de la mesa.

## Composicion y lectura

El panel se compone como pantalla fija para 1920×940 sin scroll: resumen de
64 px (jefe o vista, líneas, produciendo, en espera, atención y "en directo")
y rejilla que ocupa el alto restante. El título de página queda para lectores
de pantalla y el pie de la aplicación se oculta.

Cada tarjeta de línea presenta tres lecturas en cascada: estado (marco de
color y píldora con icono; atención con halo), orden y avance, y mesa con
tiempo global, palé actual y personas. Debajo, semáforo y cumplimiento con el
mismo cálculo y umbrales que la mesa (gris sin unidades buenas, verde ≥ 95 %,
ámbar 80-95 %, rojo < 80 % o línea bloqueada / sin operarios productivos),
ritmo actual, promedio de operarios (segundos-recurso ÷ segundos desde la
apertura de la mesa) y restante estimado. Cierra la tarjeta una frase de
acción: "Sin acción", "Esperando operarios desde…", "Finalizar la orden en la
mesa", "Revisar: conciliación NAV…".

Las tarjetas mantienen un orden fijo por centro y código de línea; la
atención se señala, no reordena.

## Actualización y fallos

La pantalla solicita una instantánea cada cinco segundos. Las consultas son de
solo lectura y no contactan NAV, RFID ni impresoras.

Si falla un refresco, se conserva la última instantánea visible y el panel se
marca como desconectado. No se sustituyen los datos por ceros ni se ocultan las
líneas. Una nueva lectura correcta retira el aviso.

RESULTADO_DESCONOCIDO se presenta como reconciliación pendiente mientras el
Worker sigue dentro de su contrato. Solo ERROR_DEFINITIVO, una impresión en
ERROR o una línea BLOQUEADA elevan el contador de atención.

## Alcance

El panel es informativo: no inicia mesas, no ficha personas, no cierra palés,
no reimprime y no finaliza órdenes. Las acciones operativas permanecen en el
terminal de producción y conservan sus controles de RFID y supervisor.
