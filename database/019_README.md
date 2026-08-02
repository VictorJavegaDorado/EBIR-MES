# Paquete 019 — maestros controlados del piloto TEST

Estado: preparado, validado con rollback y no instalado.

El paquete configura exclusivamente en `EBIR_MES_TEST` una línea, su impresora
principal, un lector RFID y tres empleados TEST: dos con rol `OPERARIO` y uno
con rol `SUPERVISOR`. También crea las asignaciones vigentes y una credencial
RFID HMAC por empleado.

Los datos físicos, personales y criptográficos no se guardan en Git. El
instalador recibe un JSON protegido fuera del repositorio, carga sus valores
mediante parámetros SQL y ejecuta `019A_maestros_piloto_test.sql` en una única
conexión. Las huellas `rfidLookupHex` deben haberse calculado con la misma clave
externa `Rfid__LookupKey` que utilizará la API; ni la clave ni los UID originales
forman parte del archivo versionado.

## Contrato del archivo externo

El JSON contiene esta estructura, sustituyendo todos los marcadores fuera del
repositorio:

```json
{
  "centerCode": "CT-01",
  "line": {
    "code": "<codigo>",
    "name": "<nombre>",
    "description": "<descripcion>"
  },
  "printer": {
    "code": "<codigo>",
    "name": "<nombre>",
    "model": "<modelo>",
    "networkName": "<dns-o-null>",
    "ipAddress": "<ip-o-null>",
    "protocol": "<protocolo>",
    "dpi": 0
  },
  "device": {
    "code": "<codigo>",
    "name": "<nombre>",
    "type": "RFID",
    "computerName": "<equipo-o-null>",
    "networkAddress": "<direccion-o-null>"
  },
  "employees": [
    {
      "navCode": "<codigo-test>",
      "fullName": "<nombre>",
      "jobTitle": "<cargo>",
      "alias": null,
      "navRole": "<rol-nav>",
      "processCode": "<proceso>",
      "laborType": "<tipo>",
      "shiftGroup": "<grupo>",
      "roleCode": "OPERARIO",
      "rfidLookupHex": "<64-hex>",
      "lastCharacters": null,
      "synchronizedNavUtc": "<fecha-utc>"
    }
  ]
}
```

La lista debe tener exactamente tres elementos, con dos `OPERARIO` y un
`SUPERVISOR`. `lastCharacters` es opcional y nunca debe contener el UID
completo.

## Secuencia autorizada

1. Ejecutar `tests/database/pilot_master_data/00_PREVUELO_019.sql` en modo de
   solo lectura.
2. Revisar los valores físicos con fabricación y sistemas.
3. Guardar el JSON en una ubicación protegida fuera de `C:\MES`.
4. Validar todo el paquete con `-ValidateOnly`; el instalador abre una
   transacción exterior y termina con `ROLLBACK`.
5. Crear un backup `COPY_ONLY`, ejecutar `RESTORE VERIFYONLY` y conservar su
   ruta como evidencia.
6. Solo con una autorización posterior, retirar `-ValidateOnly`, indicar
   `-VerifiedBackupPath` e instalar.
7. Ejecutar consultas posteriores, prueba física y `DBCC CHECKDB` en fases
   separadas.

Ejemplo de validación sin persistencia:

```powershell
.\tests\database\pilot_master_data\install-019.ps1 `
  -ConfigurationPath 'C:\ruta-protegida\pilot-019.json' `
  -ValidateOnly `
  -ConfirmAuthorizedExecution
```

El instalador rechaza otras instancias o bases, configuraciones guardadas bajo
el repositorio, valores incompletos, roles distintos, huellas que no midan 32
bytes y cualquier colisión con maestros ya existentes. El SQL vuelve a validar
las mismas condiciones dentro de una transacción y registra una auditoría sin
nombres, UID ni huellas.

La validación controlada del 02/08/2026 terminó en
`VALIDATED_AND_ROLLED_BACK`, con tres empleados y tres credenciales validados y
cero filas sintéticas restantes. La evidencia está en
`tests/database/pilot_master_data/RESULTADO_VALIDACION_2026-08-02.md`.
