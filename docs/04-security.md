# Seguridad

## Principios

- Mínimo privilegio para procesos, usuarios SQL e identidades de despliegue.
- Ningún secreto en código, configuración versionada, documentación o logs.
- Autorización en el servidor; ocultar un botón no concede ni revoca permisos.
- Validación de toda entrada externa en el límite de la aplicación.
- Auditoría de excepciones, decisiones de supervisor y correcciones manuales.
- Datos de pruebas sintéticos y fácilmente identificables.

## Base de datos

Solo se permite `EBIR_MES_TEST` en `SQL.EBIR.LOCAL\NAVISION2017`. La identidad
runtime usará los procedimientos expresamente concedidos y no acceso general a
tablas. Las migraciones se ejecutan con una identidad diferente y mediante una
fase autorizada.

## Aplicación

La autenticación y el modelo exacto de roles se definirán antes del primer
despliegue compartido. Los errores HTTP no expondrán SQL, rutas internas,
credenciales ni datos técnicos de integraciones.

