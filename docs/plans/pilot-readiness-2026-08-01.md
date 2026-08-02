# Estado de preparación del piloto — 01/08/2026

## Resultado de los nueve bloques

| Bloque | Resultado | Evidencia principal |
|---|---|---|
| 1. Contrato de lote | Completado | El lote procede de `WS_CPP_OPLanzadas.Cod_Lote_Salida`. |
| 2. Paquete 017 | Completado | Instalación, backup, prueba funcional y `DBCC CHECKDB`. |
| 3. Sincronización NAV | Completado | `FL20-02277`, lote `FL2002277`, 1 línea, 3 operaciones y 17 componentes. |
| 4. Tiempo de ejecución | Completado | Operación 20, 36 min/ud.; 10 unidades = 6 horas. |
| 5. Promoción MES | Completado | Orden MES 28 en estado `IMPORTADA`. |
| 6. Bandeja de órdenes | Completado | Endpoint real y componente probado con orden, producto, lote y tiempo. |
| 7. Impresión simulada | Completado | Paquete 018 y worker real como `Servicio de red`; `COMPLETADO/IMPRESA`. |
| 8. Toshiba, empleados y RFID | Preparación software completada; hardware bloqueado | Endpoint RFID HMAC; inventario físico sin Toshiba, lector ni empleados. |
| 9. Prueba integral | Completada en software; prueba física pendiente | 518 pruebas backend, 17 frontend y verificaciones temporales contra TEST. |

## Últimas comprobaciones integradas

- API temporal ejecutada como `NT AUTHORITY\Servicio de red`.
- La bandeja devolvió `FL20-02277`, producto `27979CI`, lote `FL2002277` y
  36 min/ud.
- Una credencial RFID mal formada devolvió 400.
- Una credencial bien formada sin clave HMAC configurada devolvió 503; no hubo
  degradación insegura ni UID en la respuesta.
- El worker simulado reservó exactamente un trabajo, generó un recibo con el
  lote NAV y confirmó una sola impresión.
- Los fixtures de impresión fueron eliminados. Permanecen únicamente las dos
  órdenes reales de entrada NAV y la orden MES 28 promovida deliberadamente.
- No se cambió IIS, `runtime\current` ni la release activa.
- No se escribió en NAV ni se invocaron codeunits.

## Estimación actual

- Piloto de software con datos TEST y periféricos simulados: **85 %**.
- Piloto físico en línea con varios operarios, Toshiba y RFID: **65 %**.

La diferencia no está en el núcleo transaccional: faltan los maestros y los
contratos físicos reales, una plantilla aprobada y el ensayo con personas y
equipos conectados.

## Preparación posterior — 02/08/2026

El paquete 019 quedó diseñado y preparado, pero no instalado. Recibe línea,
impresora, lector, empleados y huellas RFID como parámetros desde un archivo
protegido fuera del repositorio. Incluye guardas exclusivas para
`EBIR_MES_TEST`, prevuelo de solo lectura, validación completa con rollback y
auditoría resumida. Continúa bloqueado hasta revisar los valores físicos y los
tres empleados/tarjetas TEST.

La validación sintética completa del 02/08/2026 se ejecutó como
`EBIR\vjavega`, terminó con rollback y dejó cero filas `ZZ19-*`. La publicación
temporal de API y SPA volvió a devolver la orden `FL20-02277` desde TEST. No
había ningún navegador conectado a la sesión, por lo que la inspección visual
manual continúa pendiente; no se sustituyó por una simulación visual.

## Condiciones para cerrar el piloto físico

1. Publicar o confirmar una fuente NAV de empleados estrictamente de lectura.
2. Facilitar modelo/IP/protocolo/DPI de la Toshiba y una etiqueta patrón.
3. Facilitar modelo/formato del lector y tres tarjetas de TEST.
4. Dar de alta líneas, empleados, roles, impresora, lector y asignaciones en
   `EBIR_MES_TEST` mediante un paquete controlado.
5. Ejecutar el guion físico con al menos tres operarios: identificación,
   entrada/salida, paro, sustitución, cierre de dos palés del mismo lote,
   impresión, reintento y caída/reconexión.
6. Revisar la evidencia con fabricación antes de activar una nueva release o
   habilitar escrituras NAV.
