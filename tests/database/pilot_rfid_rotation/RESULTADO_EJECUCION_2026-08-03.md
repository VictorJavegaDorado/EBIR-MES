# Resultado de ejecucion del paquete 020

Fecha: 03/08/2026.

## Validacion con rollback

- Resultado: `VALIDATED_AND_ROLLED_BACK`.
- Empleados validados: 2.
- Credenciales revocadas y nuevas comprobadas: 2 y 2.
- Correlacion de validacion: `4157a6ef-ee71-4c96-9a3e-136f763ffd28`.
- Post-check: 3 credenciales activas, 3 historicas, ninguna huella nueva y
  ninguna auditoria 020 persistidas.

## Proteccion previa

- Backup `COPY_ONLY` con `CHECKSUM` y compresion:
  `D:\BBDD\EBIR_MES_TEST_pre020_20260803_143035_7962177b.bak`.
- `RESTORE VERIFYONLY WITH CHECKSUM`: correcto.

## Instalacion

- Resultado: `INSTALLED` en `EBIR_MES_TEST`.
- Empleados afectados: 2.
- Credenciales anteriores revocadas: 2.
- Credenciales nuevas activas: 2.
- Correlacion: `9bc7525b-41a5-4e1b-8c45-6f693893e151`.

## Post-check

- Credenciales historicas totales: 5.
- Credenciales activas totales: 3.
- Credenciales objetivo revocadas: 2.
- Credenciales objetivo nuevas activas: 2.
- Roles `OPERARIO` vigentes para los dos empleados: 2.
- Eventos de auditoria de la instalacion: 1.

No se registraron valores originales, huellas ni secretos. No se contacto NAV,
no se activo ninguna release y no se ejecutaron pruebas fisicas en esta fase.
