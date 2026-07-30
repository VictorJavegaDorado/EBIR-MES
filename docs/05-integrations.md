# Integraciones

## NAV

El MES encapsula NAV tras un adaptador. Los casos de uso no dependen de formatos
o transportes propios de NAV. Las operaciones salientes se persisten, se
procesan fuera de la transacción productiva y conservan estado para reintento y
diagnóstico.

## Impresión

Una acción productiva crea un trabajo de impresión persistido. El worker lo
reserva, procesa y confirma. El desbloqueo manual es una acción controlada y
auditada. Desarrollo y pruebas utilizan impresoras simuladas sin dirección de
red ni protocolo físico.

## RFID

La lectura física pertenece al borde de integración. El servidor recibe un
identificador normalizado y ejecuta las mismas reglas que para una entrada
manual autorizada. No se contactará con dispositivos hasta una fase
expresamente autorizada.

