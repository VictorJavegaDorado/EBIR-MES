# Instrucciones del backend

- Respeta la dirección de dependencias descrita en `docs/01-architecture.md`.
- Organiza `Application` por capacidad funcional y caso de uso, no por tipo
  técnico global.
- El dominio no conoce SQL, HTTP, NAV, impresoras ni RFID.
- La API traduce HTTP; no contiene reglas de negocio.
- Infraestructura implementa persistencia concreta y no expone modelos SQL al
  resto de la aplicación.
- Integraciones encapsula cada sistema externo en una carpeta con nombre
  explícito.
- Solo crea una interfaz cuando representa un límite que el caso de uso necesita
  sustituir o cuando existen varias implementaciones reales.
- No añadas dependencias NuGet sin justificar su necesidad.

