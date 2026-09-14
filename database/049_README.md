# Paquete 049 - Asignacion de jefes de linea

Estado: preparado, no instalado.

`049A_asignacion_jefes_linea.sql` crea `cfg.lineas_jefes`, la relacion vigente
entre una linea y el supervisor responsable (jefe de linea). El panel de
fabricacion la usa para mostrar a cada jefe solo sus 4-5 lineas y para
etiquetar la vista de planta.

Garantias:

- base exclusiva `EBIR_MES_TEST`;
- una linea tiene como maximo un jefe vigente (indice unico filtrado); un jefe
  puede tener varias lineas;
- la vigencia se cierra con `asignado_hasta_utc`, nunca borrando la fila;
- autor obligatorio (empleado o cuenta) y motivo opcional, como en el resto
  de asignaciones de `cfg`;
- sin datos: el reparto real se entrega en un paquete de datos posterior,
  parametrizado como los maestros del piloto;
- `mes_runtime` solo lee la tabla (SELECT sobre `cfg`, paquete 009); el rol
  `SUPERVISOR` vigente se comprueba en la consulta del panel, no en la tabla.

Si la tabla no existe, la API del panel sigue funcionando sin filtro y la
lista de jefes queda vacia; instalar el paquete activa la vista por jefe sin
cambiar la release.

Antes de instalar se requiere revision estatica, ensayo con rollback
(`tests/database/line_supervisor_assignment`), copia `COPY_ONLY` verificada y
autorizacion expresa.
