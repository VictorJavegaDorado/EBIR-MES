SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;

BEGIN TRANSACTION;

ALTER TABLE nav.componentes_orden
    ADD CONSTRAINT UQ_nav_componentes_id_orden
        UNIQUE (componente_orden_id, orden_id);

ALTER TABLE prod.sesiones_linea
    ADD CONSTRAINT UQ_prod_sesiones_id_orden_linea
        UNIQUE (sesion_linea_id, orden_id, linea_id);

COMMIT;
