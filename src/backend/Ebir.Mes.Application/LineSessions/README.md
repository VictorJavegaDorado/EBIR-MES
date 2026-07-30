# Apertura de sesión de línea

`OpenLineSession` valida el contrato de aplicación y delega la transición
atómica en `ILineSessionOpener`. Los rechazos productivos se expresan con
códigos funcionales estables; la aplicación no conoce números ni mensajes SQL.
