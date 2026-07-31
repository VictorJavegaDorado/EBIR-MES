# IIS

La preparación del piloto y el procedimiento de rollback se describen en
[`PILOT-RUNBOOK.md`](PILOT-RUNBOOK.md).

`Get-PilotPreflight.ps1` genera un inventario JSON de solo lectura del
repositorio, IIS, certificados, versiones preparadas y Worker. Para cada
release identifica el modo de hosting y comprueba la estructura superior y el
esquema mínimo de la lista de hashes. Esta comprobación estructural no sustituye
la verificación completa de cada hash antes de activar.

La activación, los cambios de IIS, la identidad del application pool y la
instalación del Worker requieren autorización explícita. No se almacenarán
secretos en `web.config`.

