# Visión general

EBIR MES coordina la ejecución de fabricación desde terminales de planta sin
convertir la interfaz en dueña de las reglas. El servidor valida las
transiciones, mantiene la trazabilidad y encapsula la comunicación con sistemas
externos.

## Objetivos

- Guiar al operario con una interfaz táctil clara.
- Impedir estados productivos incoherentes mediante operaciones transaccionales.
- Mantener trazabilidad de turnos, fichajes, producción, palés y scrap.
- Integrarse con NAV e impresión de manera reintentable y observable.
- Permitir pruebas completas sin acceder a dispositivos físicos.

## Límites actuales

La primera fase trabaja exclusivamente contra `EBIR_MES_TEST`. NAV, RFID e
impresoras se representarán mediante adaptadores simulados hasta recibir una
autorización específica de integración.

`LineIdentification` es la primera vertical de aplicación terminada a nivel de
código. Su validación automatizada no abre conexiones SQL: los contratos HTTP
usan un lector sustituido dentro del host de pruebas y los componentes
frontend sustituyen `fetch`.
