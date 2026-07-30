# Sesiones de línea

`OpenLineSession` valida el contrato de apertura y delega la transición atómica
en `ILineSessionOpener`.

`RegisterProductiveEntry` valida la sesión, el operario y la correlación antes de
delegar el fichaje en `IProductiveEntryRegistrar`.

`RegisterProductiveExit` aplica las mismas validaciones de transporte y delega
el cierre del fichaje y el recálculo de capacidad en
`IProductiveExitRegistrar`.

`MarkShiftChangePending` valida la sesión y la correlación y conserva el
resultado idempotente de `IShiftChangePendingMarker`.

Los rechazos productivos se expresan con códigos funcionales estables; la
aplicación no conoce números ni mensajes SQL.
