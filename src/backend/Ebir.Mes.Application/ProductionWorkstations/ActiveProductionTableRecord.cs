using Ebir.Mes.Application.ProductionOrders;

namespace Ebir.Mes.Application.ProductionWorkstations;

public sealed record ActiveProductionTableRecord(
    ProductionOrderSelectionRecord Order,
    ProductionTableStateRecord Table);
