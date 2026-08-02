# Cierre de preparación del piloto — 02/08/2026

Este informe continúa el estado del 01/08 y registra la preparación del paquete
019. Las reglas funcionales permanecen en
`docs/modules/pilot-master-data.md`; este documento conserva únicamente el
estado y la secuencia pendiente.

## Estado versionado

- `main`, GitHub y `C:\MES` están sincronizados en
  `b6f876549d1806c25d4e462eaad8132d74a719de`.
- El paquete 019 está preparado, validado con rollback y fusionado en `main`.
- El paquete 019 no está instalado.
- Los paquetes 001–018 continúan instalados; no se volvió a ejecutar ninguno.
- La release activa sigue siendo
  `C:\MES\runtime\releases\20260731.5-db4de52-combined`.
- No se cambió IIS, `runtime\current` ni la configuración de la release activa.
- No se escribió en NAV, no se invocaron codeunits y no se contactó hardware.

## Paquete 019

El paquete incorpora:

- `database/019A_maestros_piloto_test.sql`, lote transaccional;
- `tests/database/pilot_master_data/install-019.ps1`, carga parametrizada;
- `tests/database/pilot_master_data/00_PREVUELO_019.sql`, prevuelo de lectura;
- `tests/database/pilot_master_data/verify-019-static.ps1`, revisión sin SQL;
- documentación y resultado de la validación controlada.

Los nombres, códigos de empleados, direcciones de hardware, UID y huellas no
se guardan en Git. El instalador exige un JSON protegido fuera del repositorio,
usa parámetros SQL y rechaza otras instancias o bases. La carga requiere una
línea, una impresora principal, un lector RFID, dos operarios y un supervisor.

## Validación ejecutada

La prueba integral utilizó valores sintéticos `ZZ19-*` y la identidad
`EBIR\vjavega`. Una tarea programada temporal evitó el doble salto de
credenciales de WinRM y se eliminó al terminar.

Resultado:

- modo `VALIDATED_AND_ROLLED_BACK`;
- tres empleados y tres credenciales validados;
- relaciones de línea, impresora, lector y roles validadas;
- auditoría resumida validada;
- cero filas sintéticas restantes;
- cero tareas, listeners y artefactos temporales restantes.

No se creó backup ni se ejecutó `DBCC CHECKDB`, porque no hubo instalación.
Ambos controles siguen siendo obligatorios en una futura fase autorizada.

## Validación acumulada

- `dotnet format`: correcto;
- build Release: 0 advertencias y 0 errores;
- backend: 518 pruebas superadas;
- frontend: 17 pruebas superadas;
- TypeScript y build frontend: correctos;
- `npm audit`: 0 vulnerabilidades;
- revisión estática 019 y sintaxis PowerShell: correctas.

Se publicó temporalmente la API y la SPA y el endpoint real devolvió la orden
`FL20-02277`, producto `27979CI`, lote `FL2002277` y 36 min/ud. No había un
navegador conectado a la sesión, por lo que la inspección visual manual sigue
pendiente. La publicación, la tarea y el listener se retiraron al terminar.

## Información que debe recogerse el 03/08

### Línea

- código y nombre definitivos;
- confirmación del centro `CT-01`;
- descripción y uso en el piloto.

### Toshiba

- modelo, IP o DNS, puerto, protocolo y lenguaje;
- DPI, tamaño y orientación de etiqueta;
- velocidad, oscuridad y etiqueta patrón aprobada;
- línea asignada y condición de impresora principal.

### RFID

- fabricante, modelo e interfaz USB/serie/red;
- equipo, COM o IP/puerto y parámetros de conexión;
- formato exacto emitido, longitud, prefijo, sufijo y terminador;
- comportamiento de lecturas repetidas;
- tres tarjetas exclusivamente TEST.

### Empleados

- dos operarios y un supervisor autorizados para TEST;
- código NAV estable, nombre, cargo, proceso, mano de obra y grupo de turno;
- confirmación de fuente NAV de solo lectura o autorización de alta manual;
- asignación inequívoca de cada tarjeta TEST.

Los UID se tratarán en un archivo protegido y solo se persistirán huellas
HMAC-SHA256 de 32 bytes. La clave `Rfid__LookupKey` seguirá fuera de Git y de la
base de datos.

## Orden de continuación

1. Verificar que GitHub y `C:\MES` siguen limpios en `b6f8765` y que la release
   activa no cambió.
2. Recoger y revisar los valores reales con fabricación y sistemas.
3. Crear el JSON protegido fuera de `C:\MES`.
4. Generar o confirmar la clave HMAC externa y calcular las tres huellas sin
   registrar los UID.
5. Ejecutar el prevuelo 019 de solo lectura.
6. Ejecutar `install-019.ps1 -ValidateOnly` con los valores reales.
7. Revisar el resultado. No instalar hasta una autorización posterior y
   específica.
8. Antes de instalar: backup `COPY_ONLY` y `RESTORE VERIFYONLY`.
9. Después de instalar: comprobaciones funcionales, limpieza, `DBCC CHECKDB` y
   prueba física multioperario.

La implementación Toshiba y del lector comenzará solo cuando sus contratos
físicos estén confirmados. Las escrituras NAV y una nueva release siguen fuera
de alcance.
