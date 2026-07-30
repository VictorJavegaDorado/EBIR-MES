# Pruebas del paquete 013

Estado: **paquete completo `00–07` y `99` ejecutado y validado; fixtures
eliminados y `DBCC CHECKDB` correcto el 29/07/2026**.

Base exclusiva: `EBIR_MES_TEST`.

No usar NAV, RFID físico, dispositivos, impresoras reales ni datos de planta.

## Objetivo

Validar de extremo a extremo:

- registro de scrap por operario y supervisor;
- validaciones de sesión, componente, motivo, descripción, cantidad y rol;
- idempotencia de altas;
- acumulado de scrap sin alterar el objetivo bueno;
- revisiones y anulaciones inmutables;
- operaciones locales de consumo y ajuste NAV;
- solicitudes vinculadas a scrap y solicitudes ordinarias;
- máquina de estados de reaprovisionamiento;
- asignación exclusiva al aprovisionador;
- concurrencia, auditoría y permisos mínimos;
- limpieza completa y consistencia física de la base.

## Fixtures

Prefijos exclusivos:

```text
ZZTEST_013
ZZ13-
```

El prevuelo exigirá:

- exactamente 37 tablas;
- exactamente 20 procedimientos;
- la función interna `prod.recursos_efectivos_sesion`;
- los cuatro procedimientos `013A–013D`;
- exactamente 37 registros iniciales;
- cero filas operativas;
- `EBIR\MES$` como miembro de `mes_runtime`.

Fixtures previstos:

- una empresa NAV sintética;
- cuatro líneas;
- dos supervisores;
- dos operarios;
- dos aprovisionadores;
- un empleado sin rol funcional, para rechazos;
- tres órdenes y formatos de palé;
- dos componentes sintéticos por orden;
- sesiones y estados operativos creados por las pruebas funcionales.

No se crearán:

- credenciales RFID;
- dispositivos;
- impresoras;
- operaciones externas;
- datos o códigos reales.

## Archivos y orden

```text
00_PREVUELO_Y_FIXTURES_013.sql — preparado
01_REGISTRO_SCRAP.sql — preparado
02_REVISIONES_Y_ANULACION.sql — preparado
03_SOLICITUDES_REAPROVISIONAMIENTO.sql — preparado
04_TRANSICIONES_REAPROVISIONAMIENTO.sql — preparado
05_CONCURRENCIA_A.sql — preparado
06_CONCURRENCIA_B.sql — preparado
07_AUDITORIA_Y_PERMISOS.sql — preparado
99_LIMPIEZA_Y_CHECKDB.sql — preparado
```

La secuencia funcional será acumulativa:

```text
00 -> 01 -> 02 -> 03 -> 04 -> 05/06 -> 07 -> 99
```

Los clientes `05` y `06` se ejecutarán en conexiones independientes y
compartirán instantes UTC futuros sustituidos únicamente para la ejecución
autorizada.

## Casos de prueba

### 00. Prevuelo y fixtures

1. Rechazar restos de fixtures `ZZTEST_013`/`ZZ13-`.
2. Confirmar inventario físico y objetos `013`.
3. Confirmar catálogos iniciales y tablas operativas vacías.
4. Confirmar runtime y rol.
5. Crear exclusivamente fixtures sintéticos.
6. Confirmar ausencia de RFID, dispositivos e impresoras.

### 01. Registro de scrap

7. Abrir sesiones sintéticas con procedimientos instalados.
8. Registrar scrap por operario.
9. Registrar scrap por supervisor.
10. Validar snapshots del componente.
11. Validar incremento de `cantidad_scrap_acumulada`.
12. Confirmar que objetivo y cantidad buena no cambian.
13. Confirmar operación `CONSUMO_SCRAP` pendiente y payload JSON.
14. Repetir la correlación con los mismos parámetros.
15. Rechazar la misma correlación con parámetros distintos.
16. Rechazar cantidad cero o negativa.
17. Rechazar componente ajeno.
18. Rechazar motivo inactivo o inexistente.
19. Rechazar `OTROS` sin descripción.
20. Rechazar empleado sin rol.
21. Rechazar sesión finalizada o estado no permitido.
22. Confirmar estado transaccional limpio tras cada rechazo.

### 02. Revisiones y anulaciones

23. Corregir cantidad, componente, motivo y descripción.
24. Confirmar revisión número 1 e inmutabilidad del original.
25. Confirmar delta del acumulado.
26. Confirmar `AJUSTE_CONSUMO_SCRAP`.
27. Anular y dejar cantidad efectiva cero.
28. Confirmar `ANULACION_CONSUMO`.
29. Rechazar revisión idéntica.
30. Rechazar usuario no supervisor.
31. Rechazar acumulado negativo.
32. Rechazar revisión con última operación `PROCESANDO`.
33. Rechazar revisión con `RESULTADO_DESCONOCIDO`.
34. Admitir revisión con `ERROR_REINTENTABLE`.
35. Validar idempotencia estricta.

### 03. Solicitudes

36. Crear solicitud vinculada al valor efectivo de un scrap.
37. Crear solicitud ordinaria sin scrap.
38. Confirmar estado e historial inicial `PENDIENTE`.
39. Admitir varias necesidades reales del mismo componente.
40. Rechazar scrap anulado.
41. Rechazar componente diferente al efectivo.
42. Rechazar scrap de otra sesión, línea u orden.
43. Rechazar cantidad no positiva.
44. Rechazar solicitante sin rol.
45. Validar idempotencia estricta.

### 04. Transiciones

46. `PENDIENTE -> ACEPTADA`.
47. Confirmar asignación y `aceptada_utc`.
48. `ACEPTADA -> EN_CAMINO`.
49. `EN_CAMINO -> ENTREGADA`.
50. Rechazar transición de un segundo aprovisionador.
51. Rechazar transición desde estado terminal.
52. Rechazar salto `PENDIENTE -> ENTREGADA`.
53. Rechazar sin motivo obligatorio.
54. Rechazar una solicitud pendiente.
55. Cancelar desde `PENDIENTE`, `ACEPTADA` y `EN_CAMINO`.
56. Confirmar historial ordenado y marcas temporales.
57. Validar idempotencia estricta de cada transición.
58. Validar cálculo visual verde, amarillo y rojo mediante consulta.

### 05–06. Concurrencia

59. Dos supervisores corrigen simultáneamente el mismo scrap.
60. Una revisión y una solicitud vinculada compiten sobre el mismo scrap.
61. Dos aprovisionadores intentan aceptar la misma solicitud.
62. Aceptación y rechazo simultáneos.
63. Entrega y cancelación simultáneas.
64. Confirmar un único ganador y ausencia de revisiones o historiales
    duplicados.

### 07. Auditoría y permisos

65. Confirmar los nueve tipos de evento `013`.
66. Confirmar autor, rol, línea, orden, sesión, entidad y correlación.
67. Confirmar JSON anterior/nuevo y motivos obligatorios.
68. Confirmar ausencia de RFID, secretos y referencias externas.
69. Confirmar `EXECUTE` positivo de `EBIR\MES$` sobre `013A–013D`.
70. Confirmar escrituras directas y lectura de auditoría denegadas.
71. Confirmar `ALTER`, DDL y control denegados.

### 99. Limpieza y consistencia

72. Eliminar únicamente fixtures `ZZTEST_013`/`ZZ13-`, en orden referencial.
73. Confirmar 37 tablas, 20 procedimientos y una función interna.
74. Confirmar exactamente 37 registros iniciales.
75. Confirmar cero filas operativas y cero fixtures.
76. Confirmar pertenencia de `EBIR\MES$` a `mes_runtime`.
77. Ejecutar `DBCC CHECKDB (EBIR_MES_TEST)`.

## Autorizaciones futuras

La ejecución se separará en:

1. instalación atómica de `013A–013D`;
2. prevuelo y fixtures;
3. pruebas funcionales `01–04`;
4. concurrencia `05–06`;
5. auditoría y permisos `07`;
6. limpieza y `DBCC CHECKDB` mediante `99`.

Ninguna fase se ejecutará sin autorización explícita independiente.

## Resultado real

Con autorización expresa se instalaron `013A–013D`, se crearon los fixtures,
se ejecutaron las pruebas funcionales, los dos clientes concurrentes,
auditoría/permisos y la limpieza.

`01–04`, `07` y `99` terminaron correctamente. La primera carrera concurrente
detectó una anticipación del verificador B respecto al último commit A; se
añadieron una barrera final acotada y una guarda reanudable. La repetición de
`05–06` terminó correctamente sin cambiar procedimientos.

El detalle está en `RESULTADO_EJECUCION_2026-07-29.md`.

Estado final:

```text
37 tablas
20 procedimientos
1 función interna
37 registros iniciales
0 filas operativas
0 fixtures
EBIR\MES$ miembro de mes_runtime
DBCC CHECKDB sin errores
```

## Puente hacia la aplicación visual

Cuando `013` quede instalado, validado y limpio, el siguiente bloque será un
primer flujo vertical de aplicación:

```text
interfaz web táctil
    -> API local MES
    -> procedimientos de EBIR_MES_TEST
    -> estado actualizado de línea/sesión
```

Se utilizarán datos sintéticos y adaptadores simulados. NAV, RFID físico e
impresión real permanecerán desacoplados hasta su autorización y
configuración específica.
