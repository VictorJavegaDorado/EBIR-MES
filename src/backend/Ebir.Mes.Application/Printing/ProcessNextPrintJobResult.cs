namespace Ebir.Mes.Application.Printing;

public sealed record ProcessNextPrintJobResult(
    ProcessNextPrintJobOutcome Outcome,
    long? PrintJobId);
