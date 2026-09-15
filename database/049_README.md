# Paquete 049 - Asignacion de jefes de linea

Estado: instalado y validado el 15/09/2026 en `EBIR_MES_TEST`.

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

Se instalo en `EBIR_MES_TEST` el 15/09/2026 tras un backup `COPY_ONLY` con
checksum verificado
(`D:\BBDD\EBIR_MES_TEST_pre049_20260915_081049.bak`). El ensayo con rollback
en `tests/database/line_supervisor_assignment` corrigio primero un fallo de
aislamiento en el fixture de la comprobacion de autor (la linea reutilizada ya
tenia un jefe vigente y el indice unico se adelantaba al `CHECK` de autor);
tras usar una tercera linea sintetica libre, el ensayo termino con `Prueba 049
correcta: dos jefes, reasignacion con historial y restricciones verificadas.`
y `ROLLBACK`. Los fixtures `ZZ49-*` quedaron en cero y `DBCC CHECKDB` termino
sin errores. La tabla queda instalada y vacia; el reparto real jefe-linea se
entrega en un paquete de datos posterior, parametrizado como el 019.
