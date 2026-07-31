# Resultado de ejecucion del paquete 015

Fecha: 31/07/2026.

Destino exclusivo: `EBIR_MES_TEST` en `SQL.EBIR.LOCAL\NAVISION2017`.

## Preflight y copia

- Identidad de despliegue: `EBIR\vjavega`.
- Estado inicial: 37 tablas, 21 procedimientos y ningun objeto 015.
- Entorno activo: `EBIRTEST`.
- Copia previa: `D:\BBDD\EBIR_MES_TEST_pre015_20260731_1430.bak`.
- Modalidad: `COPY_ONLY`, `CHECKSUM`, compresion y `RESTORE VERIFYONLY` correcto.

## Instalacion

`015A_bandeja_entrada_ordenes_nav.sql` se ejecuto con autorizacion expresa. La
validacion posterior encontro las cinco tablas, `nav.aplicar_snapshot_orden` y
el `GRANT EXECUTE` para `mes_runtime`. No quedaron objetos parciales del intento
de cliente que rechazo el separador `GO`; ese intento fallo antes de iniciar el
lote y la instalacion posterior comprobo expresamente la ausencia de objetos.

Se dio de alta la configuracion real empresa `EBIR`, activa bajo `EBIRTEST`.

## Prueba extremo a extremo

La prueba se ejecuto en `MES.EBIR.LOCAL` como la identidad runtime
`EBIR\MES$`. El adaptador leyo NAV por SOAP usando solo `ReadMultiple` y el
adaptador SQL invoco el procedimiento con autenticacion integrada.

Orden real seleccionada: `29516CI/1508`, estado `Released`.

```text
lineas:       1
rutas:        2
componentes: 28
CREADA:       1
SIN_CAMBIOS:  1
ACTUALIZADA:  2 (cambio sintetico y restauracion)
```

La repeticion con la correlacion inicial devolvio el mismo identificador y el
resultado original sin crear otra fila de historial. Una correlacion nueva con
el mismo SHA-256 devolvio `SIN_CAMBIOS`. Un cambio sintetico y controlado en la
descripcion devolvio `ACTUALIZADA`; el snapshot original leido de NAV se aplico
de nuevo y tambien devolvio `ACTUALIZADA`. La validacion confirmo que la marca
`ZZTEST015` ya no estaba presente.

No se modifico NAV, IIS, RFID ni impresoras.

## Limpieza e integridad

Se eliminaron en una transaccion exclusivamente las filas de prueba de la orden
indicada. Estado final:

```text
nav.ordenes_entrada:             0
nav.lineas_orden_entrada:        0
nav.rutas_orden_entrada:         0
nav.componentes_orden_entrada:   0
nav.sincronizaciones_orden:      0
empresa EBIR activa en EBIRTEST: 1
```

`DBCC CHECKDB (EBIR_MES_TEST)` termino sin errores.
