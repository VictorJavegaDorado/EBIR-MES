# ADR 0003: registro autonomo de salidas MES dentro de NAV

## Estado

Aceptada e implementada en los cinco objetos `NAV-001A`, instalados y compilados
exclusivamente en `EbirTest`. El adaptador MES esta preparado en `main`, pero su
release y la automatizacion continua permanecen inactivas.

## Contexto

El cierre de bulto crea una salida de fabricacion `Pendiente`. MES puede
observarla y conciliarla, pero el paso autoritativo a `Registrado` pertenece a
NAV. El Report 50056 ya realiza ese trabajo para salidas historicas, aunque su
seleccion no distingue MES, su reclamacion puede competir con acciones
manuales y su ruta interna imprime desde NAV.

Activar ese informe sin aislamiento podria procesar filas ajenas, duplicar una
contabilizacion tras una recuperacion incorrecta o imprimir trabajos no
autorizados.

## Decision

Se reutiliza el Report 50056 con un modo parametrizado `SoloSalidasMES`, en vez
de reservar un nuevo objeto sin disponer de un inventario completo de IDs.

La tabla 50013 incorpora una marca explicita `Origen MES`. Una nueva operacion
`OpenClosePalletMES` la establece al cerrar el bulto, mientras
`OpenClosePallet` conserva el comportamiento heredado.

Todos los puntos de entrada comparten una reclamacion atomica. Antes de
contabilizar, NAV reconcilia movimientos por el identificador de la salida en
`External Document No.`. Las salidas MES nunca llaman a la impresion NAV.

La entrada historica de Job Queue permanece detenida. La automatizacion MES
usara una entrada independiente del mismo informe y nacera tambien detenida.

## Consecuencias

- DataCPP y las operaciones SOAP existentes mantienen compatibilidad.
- MES obtiene aislamiento verificable sin depender de linea u operario.
- La idempotencia cubre cualquier palet, no solo el que completa la orden.
- Un estado `Procesando` abandonado requiere conciliacion y no se reabre solo.
- El cambio exige modificar una tabla NAV y preparar rollback compatible con
  el nuevo campo.
- El adaptador MES usa la nueva operacion SOAP en `main`; activarlo exige una
  release posterior autorizada.
- Job Queue, canario, release MES y Worker siguen siendo fases separadas con
  autorizaciones independientes.
