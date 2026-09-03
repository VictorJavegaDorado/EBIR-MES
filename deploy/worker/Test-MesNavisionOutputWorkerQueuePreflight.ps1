[CmdletBinding()]
param(
    [string]$ServerInstance = 'SQL.EBIR.LOCAL\NAVISION2017',
    [string]$Database = 'EBIR_MES_TEST'
)

$ErrorActionPreference = 'Stop'

if ($ServerInstance -ne 'SQL.EBIR.LOCAL\NAVISION2017' -or
    $Database -ne 'EBIR_MES_TEST') {
    throw 'El prevuelo solo admite SQL.EBIR.LOCAL\NAVISION2017 / EBIR_MES_TEST.'
}

$options = [System.Data.SqlClient.SqlConnectionStringBuilder]::new()
$options.DataSource = $ServerInstance
$options.InitialCatalog = $Database
$options.IntegratedSecurity = $true
$options.Encrypt = $true
$options.TrustServerCertificate = $true
$options.ApplicationName = 'MES NAV Worker Queue Preflight'

$connection = [System.Data.SqlClient.SqlConnection]::new($options.ConnectionString)
try {
    $connection.Open()
    $command = $connection.CreateCommand()
    $command.CommandTimeout = 30
    $command.CommandText = @'
SET NOCOUNT ON;
IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Base no autorizada.', 1;
IF OBJECT_DEFINITION(OBJECT_ID(N'nav.reservar_siguiente_salida_palet'))
       NOT LIKE N'%numero_intentos < 12%'
 OR OBJECT_DEFINITION(OBJECT_ID(N'nav.fallar_salida_palet'))
       NOT LIKE N'%DISCOVER_AFTER_BASELINE%'
    THROW 51073, 'El contrato 041A no esta instalado.', 1;

SELECT COUNT_BIG(1)
FROM nav.operaciones
WHERE tipo = N'SALIDA_PALET'
  AND estado IN
      (N'PENDIENTE', N'PROCESANDO', N'ERROR_REINTENTABLE', N'RESULTADO_DESCONOCIDO');
'@
    $nonterminal = [long]$command.ExecuteScalar()
    if ($nonterminal -ne 0) {
        throw 'Existen salidas NAV no terminales antes de instalar el servicio.'
    }

    [pscustomobject]@{
        QueuePreflightConfirmed = $true
        QueuePreflightUtc = [DateTime]::UtcNow
        Database = $Database
        Nonterminal = $nonterminal
        Reconciliation041A = $true
    }
}
finally {
    $connection.Dispose()
}
