# Backend

Proyectos:

- `Ebir.Mes.Domain`: conceptos y reglas puras.
- `Ebir.Mes.Application`: casos de uso organizados por funcionalidad.
- `Ebir.Mes.Infrastructure`: persistencia SQL Server y servicios técnicos.
- `Ebir.Mes.Integrations`: NAV, impresión y RFID.
- `Ebir.Mes.Api`: transporte HTTP y composición.
- `Ebir.Mes.Worker`: procesamiento asíncrono.

La estructura interna se crea al implementar cada vertical. No se añaden
carpetas o abstracciones vacías para funcionalidades hipotéticas.

