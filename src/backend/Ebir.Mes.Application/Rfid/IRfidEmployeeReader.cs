namespace Ebir.Mes.Application.Rfid;

public interface IRfidEmployeeReader
{
    Task<RfidEmployeeRecord?> ReadAsync(
        byte[] credentialFingerprint,
        CancellationToken cancellationToken);
}
