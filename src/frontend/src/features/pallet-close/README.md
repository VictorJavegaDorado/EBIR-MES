# pallet-close

Primer corte visual del cierre manual idempotente de palé.

- `api/closePallet.ts`: contrato HTTP y traducción segura de problemas.
- `model/palletClose.ts`: comando, respuesta y estados visibles.
- `ui/PalletClosePage.tsx`: formulario táctil, reintentos, resultado y error.
- Reglas: `docs/modules/palletization.md`.
- Pruebas:
  `tests/frontend/component/features/pallet-close`.

La correlación se genera al enviar y se conserva mientras los datos no cambien.
Esto permite repetir de forma segura una solicitud cuyo resultado no llegó al
terminal. Cualquier edición invalida ese intento y la siguiente solicitud usa
una correlación nueva.

La feature solo llama al endpoint MES. No contacta NAV, RFID, impresoras ni IIS.
