# Instrucciones de Integrations

- Una carpeta por sistema externo: `Navision`, `Printing` o `Rfid`.
- No realices llamadas externas desde constructores ni durante el arranque.
- Añade tiempos de espera, idempotencia, observabilidad y una estrategia de
  reintento acorde a la operación.
- Los adaptadores reales permanecen desactivados en desarrollo y pruebas hasta
  autorización explícita.
- No copies credenciales o endpoints desde `legacy-reference`.

