# Paletización

La paletización agrupa unidades producidas en un palé trazable. El cierre manual
de un palé deberá:

- comprobar que el palé esté abierto;
- comprobar que contenga al menos una unidad válida;
- persistir el cierre de manera transaccional;
- crear el trabajo de impresión dentro de la misma operación de negocio;
- permitir que el worker imprima después, fuera de la transacción;
- ser idempotente frente a repeticiones del terminal.

Las reglas se concretarán al comenzar la vertical de paletización, contrastando
el modelo SQL ya instalado.

