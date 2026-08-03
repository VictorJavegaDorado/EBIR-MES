# Paquete 020 - rotacion RFID controlada del piloto TEST

Estado: preparado, pendiente de validacion SQL e instalacion autorizada.

El paquete rota las credenciales RFID vigentes de los dos empleados TEST con
rol `OPERARIO`. Revoca las credenciales anteriores, crea dos nuevas y registra
un unico evento de auditoria sin nombres, valores originales ni huellas.

Los valores fisicos y criptograficos permanecen fuera del repositorio. El
instalador recibe un JSON protegido, convierte las dos huellas hexadecimales en
parametros binarios y ejecuta `020A_rotacion_credenciales_rfid_piloto.sql` en
una unica conexion y dentro de una transaccion exterior.

## Guardas

- Solo admite `SQL.EBIR.LOCAL\NAVISION2017/EBIR_MES_TEST`.
- Exige exactamente los dos codigos TEST autorizados y rol `OPERARIO`.
- Ambos empleados deben estar activos y conservar una credencial vigente.
- Las dos huellas nuevas deben ser distintas y no existir en el historial.
- Un fallo revierte conjuntamente las revocaciones, altas y auditoria.
- La instalacion exige identificar un backup `COPY_ONLY` verificado.

## Secuencia

1. Ejecutar `tests/database/pilot_rfid_rotation/00_PREVUELO_020.sql` en lectura.
2. Ejecutar `verify-020-static.ps1`, que no abre SQL.
3. Validar con `install-020.ps1 -ValidateOnly`; la transaccion exterior termina
   con `ROLLBACK`.
4. Crear un nuevo backup `COPY_ONLY` con `CHECKSUM` y ejecutar
   `RESTORE VERIFYONLY`.
5. Solo con una autorizacion posterior, instalar indicando
   `-VerifiedBackupPath`.
6. Comprobar las dos credenciales revocadas, las dos nuevas activas y la
   auditoria antes de repetir la prueba fisica.

La rotacion no cambia roles, no activa releases y no contacta NAV, lectores ni
impresoras.
