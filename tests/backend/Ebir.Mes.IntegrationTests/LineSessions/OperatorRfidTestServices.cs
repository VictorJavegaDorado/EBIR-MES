using Ebir.Mes.Application.Rfid;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace Ebir.Mes.IntegrationTests.LineSessions;

internal static class OperatorRfidTestServices
{
    public const string Credential = "VALID-RFID";

    public static void AddAuthorizedOperatorRfid(
        this IServiceCollection services,
        long employeeId = 7)
    {
        services.RemoveAll<IRfidCredentialFingerprinter>();
        services.RemoveAll<IRfidEmployeeReader>();
        services.AddSingleton<IRfidCredentialFingerprinter>(new Fingerprinter());
        services.AddSingleton<IRfidEmployeeReader>(
            new Reader(new(employeeId, $"EMP-{employeeId}", "Operario Test")));
    }

    private sealed class Fingerprinter : IRfidCredentialFingerprinter
    {
        public byte[] Fingerprint(string rawCredential) => new byte[32];
    }

    private sealed class Reader(RfidEmployeeRecord employee) : IRfidEmployeeReader
    {
        public Task<RfidEmployeeRecord?> ReadAsync(
            byte[] credentialFingerprint,
            CancellationToken cancellationToken) => Task.FromResult<RfidEmployeeRecord?>(employee);
    }
}
