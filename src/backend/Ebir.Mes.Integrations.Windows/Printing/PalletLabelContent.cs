namespace Ebir.Mes.Integrations.Printing;

internal sealed record PalletLabelContent(
    string PalletCode,
    string ProductionOrderNumber,
    string ProductCode,
    string ProductDescription,
    string ProductPostingGroup,
    string Lot,
    decimal Quantity,
    string AssemblyLineName);
