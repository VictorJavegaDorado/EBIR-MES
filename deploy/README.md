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

La API se hospedará en IIS, el worker como servicio de Windows y los archivos
estáticos del frontend en IIS. Un despliegue debe crear una release completa,
validarla y cambiar `current` de manera controlada.
