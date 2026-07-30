# ADR 0001: monolito modular

Estado: aceptada.

Se adopta un monolito modular .NET con una API y un worker. La carga prevista y
la necesidad de transacciones consistentes favorecen un único despliegue lógico.
Los límites de proyecto preservan la posibilidad de separar procesos en el
futuro sin asumir ahora el coste de microservicios.

