# Paquete 050 - Seleccion propia de mesas por el jefe de linea

Estado: preparado, no instalado.

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

Antes de instalar se requiere revision estatica, ensayo con rollback
(`tests/database/line_supervisor_assignment/02_FUNCIONALES_050.sql`, que
exige el paquete 049A ya instalado), copia `COPY_ONLY` verificada y
autorizacion expresa.
