# Runbook NAV-001D

Cada bloque requiere autorizacion separada.

1. Exportar desde `NAVISION2 / EbirTest / EBIR` los Codeunits 82000 y 453 y
   guardar rollback, hashes y manifiesto fuera de Git.
2. Materializar el forward de Codeunit 82000 y comparar objetos completos.
3. Importar y compilar solo Codeunit 82000; no ejecutar interactivamente.
4. Verificar el WSDL publicado y dejar el interruptor MES apagado.
5. Construir la release MES, ejecutar pruebas simuladas y un canario sin trabajo.
6. Confirmar entrada unica `MES-SOLO-SALIDAS-V1`, estado `Listo`, usuario
   `EBIR\NAVEBIR`, fechas permitidas vigentes, cero salidas pendientes y cola de
   impresion vacia.
7. Activar `NavisionOutput__ImmediateRegistrationEnabled=true` en el servicio
   `MES NAV Worker`, reiniciarlo de forma controlada y ejecutar un unico palet.
8. Ante fallo, apagar el interruptor y reiniciar el Worker. La recurrencia de un
   minuto continua sin cambios. Si el fallo esta en el objeto, restaurar el
   Codeunit 82000 exacto y volver a compilar solo con autorizacion.

Nunca se considera exito hasta observar `Registrado` por OData y confirmar la
unica etiqueta fisica.
