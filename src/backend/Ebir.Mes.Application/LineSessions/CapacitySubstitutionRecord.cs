namespace Ebir.Mes.Application.LineSessions;

public sealed record CapacitySubstitutionRecord(
    long CapacitySubstitutionId,
    long SupervisorTimeEntryId,
    int ActiveResources);
