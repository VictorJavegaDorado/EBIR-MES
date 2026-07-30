# Pruebas del paquete 012

Estado: **paquete completamente ejecutado y validado; fixtures eliminados y
CHECKDB correcto el 29/07/2026**.

Base exclusiva: `EBIR_MES_TEST`.

## Alcance

El paquete validará:

- WC y pausa de calor;
- ausencia del último recurso;
- retorno desde `SIN_OPERARIOS`;
- sustitución supervisada sin aumentar dotación;
- retorno automático del operario sustituido;
- finalización anticipada de la sustitución;
- correcciones de fichaje y reconstrucción de tramos;
- concurrencia sobre operario y supervisor;
- auditoría y mínimo privilegio;
- limpieza total y `DBCC CHECKDB`.

No se utilizarán RFID, dispositivos, NAV, impresoras físicas ni datos reales.

## Fixtures

Prefijos exclusivos:

```text
ZZTEST_012
ZZ12-
```

El prevuelo exige:

- exactamente 37 tablas;
- exactamente 16 procedimientos;
- la función interna `prod.recursos_efectivos_sesion`;
- 37 registros iniciales;
- cero filas operativas;
- `EBIR\MES$` como miembro de `mes_runtime`.

Los fixtures contienen:

- una empresa NAV sintética;
- una impresora simulada sin red, IP ni protocolo;
- seis líneas;
- dos supervisores;
- tres operarios y un empleado de rol dual;
- cuatro órdenes y cuatro formatos.

No crean sesiones, RFID ni dispositivos.

## Archivos

- `00_PREVUELO_Y_FIXTURES_012.sql`: preparado y no ejecutado.
- `01_PAROS_Y_RETORNOS.sql`: preparado y no ejecutado.
- `02_SUSTITUCIONES.sql`: preparado y no ejecutado.
- `03_CORRECCIONES_Y_TRAMOS.sql`: preparado y no ejecutado.
- `04_DESBLOQUEO_RECURSOS_EFECTIVOS.sql`: preparado y no ejecutado.
- `05_CONCURRENCIA_A.sql`: preparado y no ejecutado.
- `06_CONCURRENCIA_B.sql`: preparado y no ejecutado.
- `07_AUDITORIA_Y_PERMISOS.sql`: preparado y no ejecutado.
- `99_LIMPIEZA_Y_CHECKDB.sql`: preparado y no ejecutado.

Todos los archivos previstos están preparados y la revisión estática conjunta
se completó.

La revisión confirmó:

- continuidad acumulativa `00→01→02→03→04→05/06→07→99`;
- códigos funcionales de prueba no duplicados;
- ausencia de referencias `ZZTEST_011`/`ZZ11-`;
- ausencia de llamadas externas;
- cardinalidades simétricas entre creación y limpieza;
- captura inmediata de estado transaccional tras errores;
- una única marca de sincronización reemplazable en cada cliente concurrente;
- conservación deliberada del dato futuro de rechazo usado en `03`;
- retorno final a 37 tablas, 16 procedimientos, una función interna,
  37 registros iniciales y cero filas operativas.

Los clientes `05–06` contienen una única marca `2099` que deberá sustituirse
en ambos, solo para la futura ejecución autorizada, por el mismo instante UTC
de entre 10 y 30 segundos en el futuro. La fecha `2099` de `03` es un dato
funcional deliberadamente futuro y no debe sustituirse.

## Autorizaciones

La futura ejecución se separará en:

1. instalación del paquete `012`;
2. prevuelo y fixtures;
3. pruebas funcionales;
4. concurrencia;
5. auditoría y permisos;
6. limpieza y `DBCC CHECKDB`.

Ninguna fase se ejecutará sin autorización explícita independiente.
