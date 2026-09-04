using Ebir.Mes.Application.PalletRecovery;

namespace Ebir.Mes.Application.ProductionWorkstations;

public sealed record ProductionTableStateRecord(
    long LineSessionId,
    long OrderId,
    long LineId,
    string State,
    DateTime? StartedAtUtc,
    DateTime ServerTimeUtc,
    long ProductiveSeconds,
    int ActiveResources,
    decimal CurrentTheoreticalCapacityPerHour,
    string PalletFormatCode,
    int UnitsPerPallet,
    IReadOnlyList<ProductionTableOperatorRecord> Operators,
    PalletRecoveryStateRecord? LatestPalletRecovery = null);
