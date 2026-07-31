# Despliegue

Esta carpeta contiene scripts, manifiestos e instrucciones versionados. Nunca
contiene una versión ejecutándose.

En el servidor MES, los artefactos generados viven en `C:\MES\runtime`:

- `bootstrap`: página temporal mientras no existe una release activa.
- `current`: enlace o directorio de la release activa.
- `releases`: publicaciones inmutables identificadas por versión.
- `shared\config`: configuración externa al repositorio.
- `shared\data`: colas y datos operativos recuperables.
- `shared\logs`: logs de aplicación e infraestructura.
- `shared\temp`: temporales prescindibles.

La API se hospedará en IIS y servirá también la SPA desde `wwwroot`; el worker
se instalará, cuando corresponda, como servicio de Windows. Un despliegue debe
crear una release completa, validarla y cambiar `current` de manera controlada.

La preparación, el preflight, la activación y el rollback del piloto se
documentan en [`iis/PILOT-RUNBOOK.md`](iis/PILOT-RUNBOOK.md).

`New-PilotRelease.ps1` compila el frontend, publica API y Worker, integra la SPA
en `api\wwwroot` y genera manifiesto y hashes SHA-256. Rechaza por defecto un
repositorio sucio y no sobrescribe una release existente. `-AllowDirty` se
reserva para candidatas de validación anteriores al commit; nunca convierte una
candidata sucia en activable.
