# Sesiones de línea

`OpenLineSession` valida el contrato de apertura y delega la transición atómica
en `ILineSessionOpener`.

`RegisterProductiveEntry` valida la sesión, el operario y la correlación antes de
delegar el fichaje en `IProductiveEntryRegistrar`.

Los rechazos productivos se expresan con códigos funcionales estables; la
aplicación no conoce números ni mensajes SQL.
