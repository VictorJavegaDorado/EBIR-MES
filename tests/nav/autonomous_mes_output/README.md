# Pruebas del registro autonomo MES en NAV

`verify-NAV-001A-static.ps1` valida la especificacion sin conectarse a NAV,
SQL, IIS, Worker o impresoras. Comprueba alcance, barreras, objetos afectados,
idempotencia, reclamacion atomica y ausencia de exportaciones protegidas.

Las pruebas funcionales descritas en `deploy/nav/NAV-001A/TEST-MATRIX.md` no
estan autorizadas por la preparacion documental del paquete.
