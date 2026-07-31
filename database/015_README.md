# Paquete 015 - bandeja idempotente de ordenes NAV

Estado: **preparado y revisable; no instalado**.

Base unica autorizable: `EBIR_MES_TEST`.

## Alcance

`015A_bandeja_entrada_ordenes_nav.sql` crea una bandeja de entrada separada de
las ordenes operativas:

- cabecera, linea, ruta y componentes recibidos de NAV;
- historial de sincronizaciones por correlacion;
- `nav.aplicar_snapshot_orden`, con serializacion por correlacion y por orden;
- hash SHA-256 del contrato completo para detectar cambios;
- resultados `CREADA`, `ACTUALIZADA` y `SIN_CAMBIOS`;
- permiso `EXECUTE` limitado al rol `mes_runtime`.

La misma correlacion y el mismo hash devuelven el resultado anterior. Reutilizar
la correlacion con otro contenido se rechaza. Una correlacion nueva con un
snapshot identico no reescribe el detalle; con contenido distinto sustituye el
snapshot completo dentro de una transaccion.

## Limite deliberado del piloto

La pagina NAV publicada no expone el numero de la linea de orden. Por ello el
contrato admite exactamente una linea de produccion por orden. La bandeja no
promueve aun datos a `prod.ordenes`: NAV no proporciona en este contrato un
lote obligatorio ni se ha confirmado la unidad de los tiempos operativos.

## Errores del contrato

```text
55500  correlacion obligatoria
55501  hash invalido
55502  JSON o cabecera invalidos
55503  correlacion reutilizada con otro snapshot
55504  bloqueo de idempotencia no disponible
55505  entorno o empresa NAV no disponibles en MES
55506  detalle incoherente
55507  la orden no tiene exactamente una linea
```

## Instalacion pendiente

El paquete tiene guardas de base y precondiciones, se instala en una transaccion
y valida objetos y permiso al terminar. Antes de ejecutarlo hacen falta una
autorizacion SQL independiente, copia de seguridad y preflight contra
`EBIR_MES_TEST`. Preparar este archivo no autoriza su ejecucion.
