# Paquete SQL — EBIR MES

Estado: paquetes `001–018` y `021A` aplicados y validados en `EBIR_MES_TEST`.

La sintaxis, las dependencias y el orden fueron validados el 27/07/2026. Todos los scripts fueron revisados y aplicados con autorización expresa sobre `EBIR_MES_TEST`.

Base permitida en esta fase: `EBIR_MES_TEST`.

## Orden

1. `001_esquemas_configuracion.sql` — aplicado.
2. `002_seguridad_nav_maestros.sql` — aplicado.
3. `003_produccion.sql` — aplicado.
4. `003A_refuerzo_relaciones_logistica.sql` — aplicado.
5. `004_logistica.sql` — aplicado.
6. `004A_refuerzo_relaciones_integracion.sql` — aplicado.
7. `005_integracion_impresion_auditoria.sql` — aplicado.
8. `006_indices_y_restricciones.sql` — aplicado.
9. `007_procedimientos_criticos.sql` — aplicado y validado el 27/07/2026.
10. `008_datos_iniciales.sql` — aplicado y validado el 27/07/2026.
11. `009_permisos_aplicacion.sql` — aplicado, corregido y validado el 27/07/2026.
12. `010_refuerzo_transacciones_procedimientos.sql` — aplicado y validado el 28/07/2026.
13. `011A–011F` — aplicados atómicamente y validados estructuralmente el 29/07/2026.
14. `012A–012I` — aplicados atómicamente y validados el 29/07/2026.
15. `013A–013D` — aplicados atómicamente y validados el 29/07/2026.
16. `014A_cerrar_palet_idempotente.sql` — aplicado atómicamente y validado el
    30/07/2026.

17. `015A_bandeja_entrada_ordenes_nav.sql` - instalado y validado el
    31/07/2026.
18. `016A_promover_ordenes_nav.sql` - instalado y validado el 01/08/2026.
19. `017A_lote_nav_ordenes_entrada.sql` - instalado y validado el 01/08/2026.
20. `018A_cola_impresion_worker.sql` - instalado y validado el 01/08/2026.
21. `021A_lote_salida_opcional.sql` - instalado y validado el 04/08/2026; permite lote de salida NAV pendiente sin inventarlo.

## Reglas

- Ejecutar con una identidad de despliegue, nunca con `EBIR\MES$`.
- Realizar copia antes de aplicar cambios sobre una base con datos.
- No ejecutar automáticamente al arrancar la aplicación.
- Cada script aborta si `DB_NAME()` no es `EBIR_MES_TEST`.
- Los scripts no contienen `DROP`, `TRUNCATE` ni borrados de datos.
- `009_permisos_aplicacion.sql` concede permisos solo sobre los esquemas MES.

## Estado posterior

- 37 tablas de usuario.
- 21 procedimientos almacenados críticos/operativos.
- 37 registros de catálogo inicial.
- 36 índices creados por el lote 006, 19 de ellos filtrados.
- 77 claves foráneas, 119 restricciones `CHECK` y 42 restricciones únicas.
- Rol `mes_runtime` asignado a `EBIR\MES$` con lectura funcional y ejecución limitada.
- Sin órdenes, empleados, líneas, impresoras ni datos productivos ficticios.
- `DBCC CHECKDB` correcto después de cada fase y al cierre.
- Los cinco procedimientos transaccionales disponen de `TRY/CATCH` y
  `ROLLBACK`; un rechazo funcional comprobado termina con
  `@@TRANCOUNT = 0` y `XACT_STATE() = 0`.
- El paquete de pruebas transaccionales críticas se ejecutó completamente el
  28/07/2026. Los fixtures se eliminaron, las tablas operativas volvieron a
  quedar vacías y `DBCC CHECKDB (EBIR_MES_TEST)` terminó sin errores.

## Pendientes para la siguiente fase

La revisión estática conjunta, la instalación controlada y la creación
autorizada de fixtures del paquete `011` se completaron el 29/07/2026. Las
pruebas funcionales `01–04` también finalizaron correctamente.

Las fases posteriores de concurrencia, permisos, limpieza y `DBCC CHECKDB`
también terminaron correctamente. La base volvió a quedar con 37 registros
iniciales y cero filas operativas.

El diseño estático inicial del siguiente bloque se documenta en
`012_DISENO_AUSENCIAS_SUSTITUCIONES_CORRECCIONES.md`. Todavía no existen
scripts `012` aplicados y no se ha ejecutado SQL para esta fase. El primer
bloque, `012A_iniciar_paro_operario.sql` y
`012B_finalizar_paro_operario.sql`, está preparado para revisión estática.
También se han preparado `012C_iniciar_sustitucion_capacidad.sql` y
`012D_finalizar_sustitucion_capacidad.sql`, junto con
`012E_corregir_fichaje_turno_actual.sql`. La definición común de recursos
efectivos queda preparada en `012F_recursos_efectivos.sql`.
`012G_refuerzo_entrada_productiva.sql` adapta la entrada productiva sin
modificar su contrato público.
`012H_refuerzo_salida_productiva.sql` aplica la misma regla común a la salida.
`012I_refuerzo_desbloqueo_recursos_efectivos.sql` completa el mismo criterio
en el desbloqueo posterior a impresión.
El orden, alcance, objetos y revisión conjunta se consolidan en
`012_README.md`.
El paquete de pruebas completo queda preparado y revisado estáticamente en
`tests/ausencias_sustituciones_correcciones`.

Con autorización expresa, `012A–012I` se instalaron después de forma atómica
en `EBIR_MES_TEST`. La base conserva 37 tablas y 37 registros iniciales, pasa
a 16 procedimientos y una función interna, y continúa sin filas operativas.
Los fixtures y las pruebas permanecen pendientes de autorización separada.

Las fases autorizadas posteriores de fixtures, pruebas funcionales,
concurrencia, auditoría, permisos y limpieza también terminaron
correctamente. El paquete `012` queda cerrado con 37 tablas, 16
procedimientos, una función interna, 37 registros iniciales, cero filas
operativas y `DBCC CHECKDB` sin errores.

El paquete `013` de scrap y reaprovisionamiento se instaló y validó
completamente el 29/07/2026. Sus pruebas funcionales, concurrencia,
auditoría/permisos, limpieza y `DBCC CHECKDB` terminaron correctamente. La
base quedó con 37 tablas, 20 procedimientos, una función interna, 37 registros
iniciales y cero filas operativas. Los fixtures `ZZTEST_013`/`ZZ13-` fueron
eliminados.

- Confirmación de los códigos reales de entorno y empresa NAV.
- Alta controlada de líneas, dispositivos e impresoras reales.
- Diseñar y desarrollar después WC/pausa de calor, sustituciones, correcciones de
  fichajes, scrap y reaprovisionamiento.
- Copia de seguridad antes de introducir datos productivos o ejecutar nuevas migraciones.

## Paquete 022 instalado y validado

`022A_formato_palet_pok.sql` persiste el formato `POK` del producto dentro del
snapshot NAV y lo incorpora atomicamente a `prod.formatos_palet_orden` durante
la promocion. Exige una unica coincidencia y unidades enteras positivas. Se
instalo en `EBIR_MES_TEST` el 05/08/2026 despues de un ensayo con rollback y un
backup `COPY_ONLY` verificado. `DBCC CHECKDB` termino sin errores. El codigo que
consume el paquete todavia no forma parte de la release activa.

## Paquete 019 preparado, no instalado

El paquete 019 carga de forma parametrizada los maestros mínimos del piloto
TEST: una línea, una impresora principal, un lector RFID y tres empleados con
roles y huellas HMAC. Los valores personales, físicos y criptográficos se
mantienen fuera del repositorio. La instalación permanece bloqueada hasta
revisar esos valores, validar con rollback y crear un backup verificado.

La validación parametrizada del 02/08/2026 creó todos los maestros dentro de
una transacción exterior y terminó con rollback. Una consulta posterior contó
cero filas sintéticas `ZZ19-*`; el paquete continúa sin instalar.

## Paquete 015 instalado y validado

`nav.aplicar_snapshot_orden` y sus tablas de bandeja reciben de forma
idempotente cabecera, linea, ruta y componentes leidos de NAV. El diseno no
escribe en NAV ni promociona aun la orden a produccion. El alcance, contrato y
errores se detallan en `015_README.md`. Se instalo con copia previa y se valido
extremo a extremo con NAV TEST el 31/07/2026; los fixtures fueron eliminados y
`DBCC CHECKDB` termino sin errores.

## Paquete 014 instalado y validado

`prod.cerrar_palet_idempotente` es el contrato seguro para la API de
paletización. Serializa por correlación, devuelve el mismo palé ante una
repetición idéntica y rechaza reutilizaciones incompatibles. También traslada
el permiso de `mes_runtime` desde el contrato anterior. La instalación está
protegida por precondiciones, transacción y validación posterior. Las pruebas
ejecutadas forzaron contención observable entre dos clientes y separaron la
limpieza de fixtures de `DBCC CHECKDB`.

El paquete se instaló y todas sus fases terminaron correctamente el 30/07/2026.
Los fixtures fueron eliminados, la base quedó con 37 tablas, 21 procedimientos,
una función interna y cero filas operativas, y `DBCC CHECKDB` no encontró
errores.
