# Pruebas del paquete 011

Estado: **paquete completo 00–07 y 99 ejecutado y validado el 29/07/2026**.

Destino exclusivo: `EBIR_MES_TEST`.

No usar NAV, RFID físico, impresoras reales ni datos de planta.

## Fixtures propuestos

Prefijo global:

```text
ZZTEST_011
```

Datos:

- empresa NAV sintética;
- seis líneas sintéticas con estados operativos;
- una impresora simulada sin IP, red o protocolo;
- un supervisor;
- tres operarios;
- un empleado con roles `OPERARIO` y `SUPERVISOR`;
- una FL `NORMAL`;
- una FL `MULTILINEA`, preparada para abrirse en dos líneas;
- formatos de 20 unidades;
- objetivo suficiente para reservas y palés.

No se crearán RFID ni dispositivos.

## Casos y orden

### A. Apertura de sesión

1. Abrir sesión normal en línea libre.
2. Rechazar otra sesión en la misma línea.
3. Rechazar otra línea para la misma FL `NORMAL`.
4. Permitir dos líneas para una FL `MULTILINEA`.
5. Rechazar línea bloqueada o sin estado operativo.
6. Rechazar formato ajeno a la orden.
7. Validar mediante tabla de casos la asignación:
   - 05:59 → `TARDE`, fecha anterior;
   - 06:00 → `MANANA`, fecha actual;
   - 13:59 → `MANANA`;
   - 14:00 → `TARDE`;
   - 21:59 → `TARDE`;
   - 22:00 → `TARDE` con advertencia.

La rama horaria real del procedimiento se probará según la hora de ejecución;
la tabla de casos verificará siempre la fórmula completa.

### B. Entrada productiva

8. Primer operario inicia sesión y línea.
9. Crear automáticamente la primera reserva.
10. Crear primer tramo con un recurso.
11. Segundo operario cierra el tramo anterior y abre otro con dos recursos.
12. Rechazar doble fichaje del mismo empleado.
13. Rechazar empleado activo en otra línea.
14. Rechazar supervisor ordinario.
15. Rechazar empleado con roles simultáneos `OPERARIO` y `SUPERVISOR`.

### C. Salida productiva

16. Salida de un recurso: queda un recurso y nuevo tramo.
17. Salida del último: sesión y línea `SIN_OPERARIOS`.
18. Regreso desde `SIN_OPERARIOS`: no duplicar la reserva inicial.
19. Rechazar salida con paro abierto.
20. Rechazar salida con sustitución activa.

### D. Cambio de turno

21. Rechazar marcado antes del límite.
22. Marcar después del límite.
23. Segunda llamada idempotente sin duplicar auditoría.
24. La sesión continúa abierta y sus fichajes/reserva permanecen.

### E. Fin de turno

25. Rechazar con reserva activa.
26. Cancelar reserva con supervisor y motivo.
27. Finalizar sesión.
28. Cerrar fichajes, paros, sustituciones, paradas y tramo.
29. Liberar línea.
30. Conservar orden reanudable.
31. Confirmar que no se crea ninguna salida NAV parcial.
32. Rechazar con salida NAV o etiqueta pendiente.

### F. Desbloqueo después de impresión

33. Cerrar palé ordinario.
34. Confirmar NAV de forma local.
35. Salir el último operario durante `PENDIENTE_NAV`.
36. Confirmar impresión local.
37. Comprobar sesión y línea `SIN_OPERARIOS`, no `PRODUCIENDO`.

### G. Concurrencia y seguridad

38. Dos entradas simultáneas del mismo empleado en líneas distintas.
39. Dos aperturas simultáneas sobre una FL `NORMAL`.
40. Verificar `@@TRANCOUNT = 0` y `XACT_STATE() = 0` tras rechazos.
41. Verificar auditoría completa.
42. Verificar permisos positivos y negativos de `EBIR\MES$`.
43. Limpiar todos los fixtures.
44. Confirmar 37 registros iniciales y tablas operativas vacías.
45. Ejecutar `DBCC CHECKDB`.

## Archivos previstos

```text
00_PREVUELO_Y_FIXTURES_011.sql        — preparado
01_APERTURA_Y_ENTRADAS.sql            — preparado
02_SALIDAS_Y_RETORNO.sql              — preparado
03_CAMBIO_Y_FIN_TURNO.sql             — preparado
04_DESBLOQUEO_IMPRESION.sql           — preparado
05_CONCURRENCIA_A.sql                 — preparado
06_CONCURRENCIA_B.sql                 — preparado
07_AUDITORIA_Y_PERMISOS.sql           — preparado
99_LIMPIEZA_Y_CHECKDB.sql             — preparado
```

Los clientes `05` y `06` se ejecutarán en conexiones distintas. Antes de una
futura ejecución autorizada deben sustituirse en ambos archivos las dos marcas
`2099-01-01` por los mismos instantes UTC: uno para la carrera de entrada y
otro posterior para la carrera de apertura. Las guardas impiden ejecutar por
accidente con los valores de plantilla.

El bloque `99` requiere autorización separada. Elimina exclusivamente los
fixtures identificados, revierte toda la transacción si el estado final no
coincide con los 37 registros iniciales y ejecuta `DBCC CHECKDB` después de
confirmar la limpieza.

La revisión conjunta del 29/07/2026 confirmó la cobertura de los casos `01–45`
y reforzó el prevuelo para exigir, antes de crear fixtures, 37 tablas, 11
procedimientos, 37 registros iniciales, tablas operativas vacías y permisos
runtime intactos.

El 29/07/2026 se ejecutó con autorización separada
`00_PREVUELO_Y_FIXTURES_011.sql`. Resultado:

```text
1 empresa NAV sintética
1 impresora simulada
6 líneas y 6 estados de línea
5 empleados y 6 asignaciones de rol
4 órdenes y 4 formatos
0 sesiones
0 RFID
0 dispositivos
```

Con una tercera autorización se ejecutaron después `01–04`. Los cuatro bloques
terminaron correctamente. Durante el primer intento de `03` se detectó un
falso positivo del propio test al evaluar `XACT_STATE()` dentro de una
sentencia que también leía tablas. Se corrigió para capturar el estado
inmediatamente después del `CATCH`, se hizo reanudable desde su preparación
válida y `03–04` finalizaron correctamente.

Estado validado antes de concurrencia:

```text
5 sesiones
1 sesión FINALIZADA_TURNO
1 palé de impresión
1 salida NAV local confirmada
1 etiqueta impresa
L06 SIN_OPERARIOS
2 fichajes abiertos
3 reservas activas
```

Con una cuarta autorización se ejecutaron `05–06` mediante dos conexiones
independientes y dos marcas UTC comunes sustituidas solo en memoria. Un primer
intento no llegó a ejecutarse por usar una subconsulta directamente como
parámetro de `EXEC`, sintaxis no admitida por SQL Server; ambos clientes se
corrigieron para declarar previamente `@supervisor_id`.

Resultado de la repetición:

```text
ganador entrada OP2: L04
ganador apertura FL NORMAL: L02
1 fichaje abierto de OP2
1 sesión activa para ZZ11-FL-TURNO
3 fichajes abiertos totales
5 sesiones activas totales
```

Con una quinta autorización se ejecutó `07_AUDITORIA_Y_PERMISOS.sql`. Se
confirmaron los diez tipos de auditoría esperados, la atribución y correlación
de eventos, la ausencia de referencias RFID y los permisos efectivos positivos
y negativos de `EBIR\MES$`. El cambio temporal de identidad terminó con
`REVERT`.

Con una sexta autorización se ejecutó `99_LIMPIEZA_Y_CHECKDB.sql`. Los fixtures
se eliminaron dentro de una transacción y `DBCC CHECKDB` terminó sin errores.

Estado final:

```text
37 tablas
11 procedimientos
37 registros iniciales
0 filas operativas
0 fixtures ZZTEST_011/ZZ11-
EBIR\MES$ miembro de mes_runtime
DBCC CHECKDB correcto
```
