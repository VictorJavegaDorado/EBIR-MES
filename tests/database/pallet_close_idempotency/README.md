# Pruebas del paquete 014

Estado: **ejecutadas correctamente el 30/07/2026**.

Destino exclusivo: `EBIR_MES_TEST`.

La validación autorizada usó fixtures `ZZTEST_014` / `ZZ14-` y cubrió:

1. cierre ordinario con un único palé, operación NAV y etiqueta;
2. repetición idéntica con el mismo `palet_id` y sin filas adicionales;
3. reutilización de correlación con parámetros distintos, esperando exactamente
   `55403`, sin filas parciales ni transacciones abiertas;
4. correlación usada por otra operación, esperando `55402`;
5. propagación representativa de `51400`; la traducción backend cubre
   estáticamente `51400–51409`;
6. dos clientes concurrentes con la misma correlación y exactamente los mismos
   parámetros (incluido el empleado), mismo `palet_id`, un palé, una operación
   NAV local, una etiqueta y un evento `PALET_CERRADO`;
7. dos correlaciones concurrentes sobre la misma reserva, un único ganador y
   un único rechazo `51403`, sin filas ni transacciones parciales;
8. permiso efectivo limitado a `EXECUTE` para `mes_runtime`;
9. limpieza total de fixtures;
10. `DBCC CHECKDB` en una autorización independiente.

Fases ejecutadas correctamente:

- `00_PREVUELO_Y_FIXTURES_014.sql`;
- `01_FUNCIONALES_014.sql`;
- `05_CONCURRENCIA_A_014.sql` y `06_CONCURRENCIA_B_014.sql`;
- `07_PERMISOS_014.sql`;
- `99A_LIMPIEZA_014.sql`;
- `99B_DBCC_014.sql`.

Los clientes de concurrencia se ejecutan en conexiones independientes con la
misma marca UTC futura. El cliente A mantiene cada cierre en una transacción
exterior durante cinco segundos y B entra un segundo después; B exige una espera
de al menos dos segundos para demostrar contención real. Las barreras de
auditoría sintéticas, con autor válido, se usan únicamente para reunir los
resultados después de que ambos clientes terminen. Ninguna prueba contacta NAV,
RFID o impresoras.

El resultado completo, incluidos tiempos, comprobaciones posteriores y
limpieza, está documentado en
`RESULTADO_EJECUCION_2026-07-30.md`.
