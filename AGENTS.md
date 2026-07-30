# Instrucciones para agentes

## Propósito

Este repositorio contiene el MES de EBIR. La organización permite localizar por
el mismo nombre funcional la documentación, el backend, el frontend y las
pruebas de cada cambio.

## Antes de editar

1. Lee este archivo.
2. Lee los `AGENTS.md` de las carpetas que vayas a modificar.
3. Consulta únicamente la documentación del módulo afectado en `docs/modules`.
4. Revisa `docs/functional-map.md` y localiza una implementación similar.
5. Limita el cambio a la funcionalidad solicitada.

## Reglas de arquitectura

- El backend es un monolito modular .NET. Los proyectos separan dominio,
  aplicación, infraestructura, integraciones, API y procesos en segundo plano.
- El frontend se organiza por funcionalidad: `app`, `features`, `entities`,
  `widgets` y `shared`.
- Usa nombres funcionales equivalentes en documentación, backend, frontend y
  pruebas.
- Cada archivo tiene una responsabilidad clara.
- No crees interfaces, clases base, repositorios genéricos ni abstracciones
  preventivas. Una abstracción debe responder a una necesidad real del dominio
  o a un límite externo concreto.
- No hagas refactorizaciones ajenas al alcance solicitado.
- Las integraciones externas se encapsulan en `Ebir.Mes.Integrations`; nunca
  deben filtrarse detalles de NAV, RFID o impresión al dominio.

## Base de datos y seguridad

- Instancia autorizada: `SQL.EBIR.LOCAL\NAVISION2017`.
- Única base autorizada: `EBIR_MES_TEST`.
- Está prohibido consultar, modificar o utilizar cualquier otra base.
- No ejecutes SQL sin autorización explícita para la fase concreta.
- No llames a NAV, RFID físico ni impresoras reales desde desarrollo o pruebas.
- No guardes contraseñas, cadenas de conexión ni secretos en el repositorio.
- Los scripts SQL son versionados e inmutables una vez aplicados; una corrección
  posterior se entrega en un nuevo paquete.

## Calidad

- Añade pruebas en el mismo cambio funcional.
- Las operaciones que cambian estado deben ser transaccionales e idempotentes
  cuando puedan repetirse desde planta.
- Registra auditoría para decisiones de supervisor, correcciones y acciones
  operativas relevantes.
- Antes de entregar, compila y ejecuta las validaciones disponibles.

## Código y runtime

- `C:\MES` es la raíz del repositorio en el servidor MES.
- `runtime` contiene únicamente despliegues y estado operativo generado; está
  ignorado por Git.
- No escribas código fuente, pruebas ni documentación dentro de `runtime`.
- No guardes configuración operativa, colas, logs o temporales fuera de
  `runtime\shared`.
