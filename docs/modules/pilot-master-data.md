# Maestros del piloto TEST

El paquete 019 prepara los maestros mínimos para la prueba física integrada:
una línea, una impresora principal, un lector RFID y tres empleados TEST con
roles y credenciales vigentes.

## Reglas

- Solo puede ejecutarse contra `EBIR_MES_TEST` en
  `SQL.EBIR.LOCAL\NAVISION2017`.
- La configuración exige exactamente dos operarios y un supervisor.
- Los roles `OPERARIO` y `SUPERVISOR` y el centro de trabajo deben existir y
  estar activos antes de ejecutar el paquete.
- Los códigos de línea, impresora, lector y empleados, y las huellas RFID,
  deben ser nuevos. Un estado parcial se rechaza; no se actualizan maestros
  existentes de forma implícita.
- La impresora requiere modelo, protocolo, resolución y dirección revisados.
- El lector debe declarar el equipo o dirección donde se conectará.
- Cada empleado recibe una huella HMAC-SHA256 distinta de 32 bytes. El UID y la
  clave HMAC nunca se persisten ni se versionan.
- Los datos físicos, personales y criptográficos se suministran desde un
  archivo protegido fuera del repositorio y llegan a SQL como parámetros.
- La línea queda vinculada a una única impresora principal y a un único lector
  activo.
- La instalación registra una auditoría resumida sin nombres ni credenciales.

## Entrega y activación

`database/019A_maestros_piloto_test.sql` es el lote transaccional y
`tests/database/pilot_master_data/install-019.ps1` es la única entrada
operativa admitida. La primera ejecución debe usar `-ValidateOnly`, que revierte
la transacción exterior después de validar todas las inserciones y relaciones.

Preparar el paquete no autoriza instalarlo. Antes de persistir datos se deben
revisar los valores reales, crear y verificar un backup y recibir autorización
expresa para esa fase. La instalación tampoco habilita el worker, activa una
release ni contacta NAV, RFID o impresoras.

## Rotacion de credenciales del piloto

Una credencial RFID ya instalada no se sustituye editando el paquete 019. La
rotacion se entrega en un paquete posterior e inmutable que recibe un archivo
protegido fuera del repositorio, revoca la credencial activa, crea la nueva y
registra una auditoria resumida. La operacion debe ser transaccional: ningun
empleado puede quedar sin credencial activa si falla el alta nueva.

Los valores originales de las tarjetas nunca se muestran ni se persisten. Una
credencial expuesta por un canal no protegido se considera comprometida y no
se provisiona.
