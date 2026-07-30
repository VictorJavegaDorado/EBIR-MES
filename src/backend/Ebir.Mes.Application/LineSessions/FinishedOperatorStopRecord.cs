namespace Ebir.Mes.Application.LineSessions;

public sealed record FinishedOperatorStopRecord(
    long OperatorStopId, long? FinishedSubstitutionId, int ActiveResources);
