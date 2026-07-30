# Arquitectura

La aplicación se construye como un monolito modular desplegable en dos procesos:
una API ASP.NET Core y un worker para tareas asíncronas. Ambos comparten
aplicación, dominio, infraestructura e integraciones. El cliente es una SPA
React.

## Dependencias permitidas

```text
API ───────────────▶ Application ◀────────────── Worker
                         │
                         ▼
                       Domain

Infrastructure ─────▶ Application
Integrations ────────▶ Application
```

`Domain` no depende de ningún otro proyecto. `Application` expresa los casos de
uso. `Infrastructure` persiste en SQL Server. `Integrations` contiene los
adaptadores de NAV, impresión y RFID. La composición de dependencias se realiza
en API y Worker.

No se separarán microservicios ni se introducirán buses, repositorios genéricos
o capas adicionales sin una necesidad demostrada.

## Separación entre repositorio y ejecución

`C:\MES` es la raíz del repositorio en `MES.EBIR.LOCAL`. El único directorio
mutable dentro de esa raíz es `runtime`, ignorado por Git. Código, documentación
y scripts nunca se escriben en `runtime`; publicaciones, configuración, datos,
logs y temporales nunca se mezclan con `src`.

La estructura operativa detallada se mantiene en `deploy/README.md`.
