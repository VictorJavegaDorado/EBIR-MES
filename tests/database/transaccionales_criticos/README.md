# Paquete independiente de pruebas transaccionales MES

Estado: **preparado para revisión; no ejecutado**.

Destino exclusivo: `SQL.EBIR.LOCAL\NAVISION2017`, base `EBIR_MES_TEST`.
No forma parte de `001–009` y no llama a NAV, SOAP, OData, impresoras, colas
ni recursos de red. NAV e impresión se simulan invocando procedimientos locales.

## Orden

1. `00_PREVUELO_Y_FIXTURES.sql`
2. `01_PRUEBAS_SECUENCIALES.sql`
   - La ejecución del 28/07/2026 quedó detenida después del caso 2.
   - No volver a ejecutar este archivo desde el principio con los fixtures actuales.
   - Continuar mediante `01B_REANUDAR_CASOS_3_A_8.sql`.
3. `02_CONCURRENCIA_SESION_A.sql`
4. `03_CONCURRENCIA_SESION_B.sql`
5. `04_AUDITORIA_Y_PERMISOS.sql`
6. `99_LIMPIEZA_Y_CHECKDB.sql`

Ningún archivo debe ejecutarse hasta recibir autorización expresa.

## Reanudación vigente

Después de aplicar el paquete `010`, el archivo vigente para continuar es
`01B_REANUDAR_CASOS_3_A_8.sql`. Antes de escribir comprueba que:

- `ZZT-FL-TX-01` tiene 0 buenas, 20 reservadas y estado `ABIERTA`;
- existe exactamente una reserva activa de 20 en su sesión;
- la línea continúa en `PRODUCIENDO`;
- la conexión comienza con `@@TRANCOUNT = 0` y `XACT_STATE() = 0`.

Si alguna precondición no coincide, aborta sin ejecutar los casos.

Todos los fixtures usan `ZZTEST_MES_TX_20260728`, `ZZT-TX-*`,
`ZZT-EMP-TX-*` o `ZZT-FL-TX-*`. No se crean RFID, dispositivos ni direcciones
de impresora. Cada script aborta fuera de `EBIR_MES_TEST`.

Los archivos `02` y `03` se ejecutan en dos ventanas SSMS con una misma hora
UTC fijada unos segundos en el futuro. La hora debe encontrarse dentro de los
dos minutos siguientes; el valor de plantilla `2099-01-01` provoca un error
inmediato y evita una espera accidental. Solo una reserva debe confirmar. El
script B comprueba que queda exactamente una reserva activa y que los
acumulados finales son 80 buenas, 20 reservadas y objetivo 100.

## Caso funcional 7A

Una FL multilínea sintética tiene objetivo 40 y dos sesiones en líneas
distintas. Cada línea reserva 20. La primera cierra un palé ordinario y la
segunda conserva su reserva activa. El cierre de la segunda reserva se rechaza
sin supervisor (`51407`) y se acepta al repetirlo con supervisor, quedando 40
unidades buenas, cero reservadas y la FL en `PENDIENTE_CIERRE`.

La rama defensiva `51409` no se fuerza mediante datos incoherentes. Su posible
refuerzo se documentará y revisará, si procede, en un paquete SQL separado.

La prueba de permisos comprueba los cinco procedimientos operativos concedidos,
la denegación de acceso directo a auditoría y la ausencia de escritura directa
en producción, operaciones NAV y trabajos de impresión.

La limpieza y `DBCC CHECKDB` del archivo `99` requieren autorización separada.
