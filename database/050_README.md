# Paquete 050 - Seleccion propia de mesas por el jefe de linea

Estado: instalado y validado el 15/09/2026 en `EBIR_MES_TEST`.

`050A_asignacion_mesas_propia.sql` crea `cfg.asignar_mesas_propias`, el
contrato transaccional que usa el panel de fabricacion para que un jefe de
linea declare, desde su propia pantalla, el conjunto de lineas que quiere ver.
Sustituye la idea de un reparto fijo cargado por SQL: el jefe se identifica
por RFID en el panel (`/api/supervisor-access/rfid`, ya instalado) y elige sus
mesas en una pantalla de seleccion; el panel llama a este contrato para
guardarlas.

Garantias:

- base exclusiva `EBIR_MES_TEST`;
- exige un empleado con rol `SUPERVISOR` vigente (`57001` en caso contrario);
- una linea con jefe vigente distinto queda bloqueada: el procedimiento
  aborta sin modificar ninguna fila (`57004`), igual que si estuviera
  deshabilitada en la pantalla de seleccion;
- las lineas propias que el jefe deja de querer ver cierran su vigencia
  (`asignado_hasta_utc`) sin borrar el historial, quedando libres para
  cualquier otro jefe;
- valida la lista de lineas antes de abrir la transaccion (`57002` lista no
  valida, `57003` linea inexistente o inactiva);
- el chequeo de conflicto usa `WITH (UPDLOCK, HOLDLOCK)` sobre las vigencias
  implicadas para que dos guardados simultaneos no puedan asignar la misma
  linea libre a dos jefes distintos;
- `mes_runtime` solo tiene `EXECUTE` sobre el contrato.

Se instalo en `EBIR_MES_TEST` el 15/09/2026 tras un backup `COPY_ONLY` con
checksum verificado
(`D:\BBDD\EBIR_MES_TEST_pre050_20260915_130248.bak`;
`RESTORE VERIFYONLY WITH CHECKSUM` correcto). El contrato quedo creado
(`cfg.asignar_mesas_propias`, `OBJECT_ID = 436196604`).

El primer ensayo
(`tests/database/line_supervisor_assignment/02_FUNCIONALES_050.sql`) revelo
que el contrato, al abrir y cerrar su propia transaccion (mismo refuerzo del
paquete 010), no puede invocarse dentro de una transaccion exterior abierta:
su `ROLLBACK` ante el rechazo esperado 57004 revertia tambien los fixtures de
la prueba. Se corrigio el ensayo (no el contrato) para confirmar los fixtures
antes de invocar el procedimiento y limpiarlos de forma explicita al final,
tanto si la prueba pasa como si falla. El ensayo repetido termino con
`Prueba 050 correcta: seleccion propia, bloqueo de linea ajena, liberacion
con historial y validaciones verificadas. Fixtures ZZ50 eliminados.` Los
fixtures `ZZ50-*` quedaron en 0/0/0 y `DBCC CHECKDB` termino sin errores.

La tabla `cfg.lineas_jefes` sigue vacia: el reparto real se construye cuando
cada jefe se identifica y selecciona sus mesas desde el propio panel.
