/* Paquete 014: integridad posterior independiente. No ejecutar sin autorizacion. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 57950, 'Pruebas permitidas unicamente en EBIR_MES_TEST.', 1;

DBCC CHECKDB (N'EBIR_MES_TEST') WITH NO_INFOMSGS, ALL_ERRORMSGS;

PRINT N'DBCC 014: OK';
