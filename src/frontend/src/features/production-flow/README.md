# Flujo operativo de producción

Pantalla única para el recorrido del operario:

1. identificación de línea;
2. selección de orden;
3. identificación RFID del equipo;
4. gestión de palés;
5. confirmación NAV y salida;
6. liberación de línea.

La interfaz usa los contratos MES existentes y no simula transiciones. Los
pasos sin contrato backend permanecen visibles y bloqueados. Las credenciales
RFID se envían para identificación, se eliminan del campo inmediatamente y no
se incorporan al estado de la pantalla.
