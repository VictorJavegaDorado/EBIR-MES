# Paquete 016: promocion controlada de ordenes NAV

Promueve un snapshot validado de `nav.*_entrada` a `prod.ordenes` sin volver a
consultar ni escribir en NAV.

El lote y la operacion productiva son decisiones explicitas del piloto. El
tiempo se toma de `nav.rutas_orden_entrada.tiempo_ejecucion`; la operacion debe
existir una sola vez y el valor debe poder representarse exactamente como
minutos por unidad con un decimal.

Resultados:

- `CREADA`: primera promocion y alta atomica de orden y componentes;
- `SIN_CAMBIOS`: nueva correlacion con el mismo snapshot, lote y operacion;
- `REVISION`: cambio de snapshot o de decisiones manuales. No se sobrescriben
  datos productivos y la orden queda en estado `REVISION`.

La misma correlacion solo puede repetirse con los mismos parametros y snapshot.
La ejecucion requiere autorizacion especifica y se limita a `EBIR_MES_TEST`.
