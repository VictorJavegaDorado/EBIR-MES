namespace Ebir.Mes.Application.Rfid;

public interface ISupervisorRfidReader
{
    Task<RfidEmployeeRecord?> ReadAsync(
        byte[] credentialFingerprint,
        CancellationToken cancellationToken);
}
