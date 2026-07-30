SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;

BEGIN TRANSACTION;

ALTER TABLE prod.palets
    ADD CONSTRAINT UQ_prod_palets_id_orden
        UNIQUE (palet_id, orden_id);

ALTER TABLE [log].revisiones_scrap
    ADD CONSTRAINT UQ_log_revisiones_id_scrap_orden
        UNIQUE (revision_scrap_id, scrap_id, orden_id);

COMMIT;
