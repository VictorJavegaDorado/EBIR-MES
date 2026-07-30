# Resultado de ejecución del paquete 011 — 29/07/2026

## Alcance

```text
Instancia: SQL.EBIR.LOCAL\NAVISION2017
Base única: EBIR_MES_TEST
```

No se consultó ni utilizó ninguna otra base. No hubo llamadas a NAV, RFID
físico, dispositivos o impresoras reales.

## Fases autorizadas

1. Instalación atómica de `011A–011F`.
2. Prevuelo y creación de fixtures `ZZTEST_011`/`ZZ11-`.
3. Pruebas funcionales `01–04`.
4. Concurrencia `05–06` en dos conexiones.
5. Auditoría y permisos `07`.
6. Limpieza y `DBCC CHECKDB` mediante `99`.

## Resultados funcionales

- Apertura normal y multilínea correcta.
- Rechazos de línea ocupada, FL normal duplicada y formato ajeno.
- Regla horaria y fecha operativa correctas.
- Primera entrada con reserva automática.
- Tramos de uno y dos recursos.
- Rechazo de doble fichaje, supervisor ordinario y empleado dual.
- Salidas, dotación cero y retorno sin duplicar reserva.
- Rechazos con paro y sustitución.
- Cambio de turno pendiente e idempotente.
- Rechazo de fin de turno con reserva, NAV o etiqueta pendiente.
- Cancelación supervisada y fin de turno completo.
- Sin salida NAV parcial al finalizar turno.
- Desbloqueo posterior a impresión hacia `SIN_OPERARIOS`.
- Concurrencia con un único ganador para fichaje y FL normal.
- Auditoría completa y permisos mínimos efectivos.

## Incidencias corregidas durante la ejecución

1. `03_CAMBIO_Y_FIN_TURNO.sql` producía un falso positivo al evaluar
   `XACT_STATE()` en una sentencia que también consultaba tablas. Se capturó el
   estado inmediatamente después del `CATCH` y se permitió reanudar únicamente
   desde la preparación parcial exacta.
2. Los clientes `05–06` usaban una subconsulta directamente como argumento de
   `EXEC`, sintaxis no admitida por SQL Server. Se declaró previamente
   `@supervisor_id` en ambos clientes. El intento fallido fue solo de
   compilación y no modificó datos.

## Estado final

```text
37 tablas
11 procedimientos
37 registros iniciales
0 filas operativas
0 fixtures ZZTEST_011/ZZ11-
EBIR\MES$ miembro de mes_runtime
DBCC CHECKDB correcto
```
