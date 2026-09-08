using Ebir.Mes.Application.Rfid;
using Xunit;

namespace Ebir.Mes.Application.Tests.Rfid;

public sealed class AuthorizeOperatorByRfidTests
{
    [Fact]
    public async Task AuthorizesOnlyTheSelectedOperator()
    {
        var useCase = CreateUseCase(new(7, "EMP-7", "Operario Test"));

        var result = await useCase.ExecuteAsync(7, "VALID-RFID", CancellationToken.None);

        Assert.True(result.Authorized);
        Assert.Null(result.ErrorCode);
    }

    [Fact]
    public async Task RejectsAnotherOperatorsCard()
    {
        var useCase = CreateUseCase(new(8, "EMP-8", "Otro Operario"));

        var result = await useCase.ExecuteAsync(7, "OTHER-RFID", CancellationToken.None);

        Assert.False(result.Authorized);
        Assert.Equal("RFID_OPERATOR_MISMATCH", result.ErrorCode);
    }

    [Fact]
    public async Task RejectsAnUnknownCredential()
    {
        var useCase = CreateUseCase(null);

        var result = await useCase.ExecuteAsync(7, "UNKNOWN-RFID", CancellationToken.None);

        Assert.False(result.Authorized);
        Assert.Equal("RFID_CREDENTIAL_NOT_FOUND", result.ErrorCode);
    }

    private static AuthorizeOperatorByRfid CreateUseCase(RfidEmployeeRecord? employee) =>
        new(new IdentifyEmployeeByRfid(new Fingerprinter(), new Reader(employee)));

    private sealed class Fingerprinter : IRfidCredentialFingerprinter
    {
        public byte[] Fingerprint(string rawCredential) => new byte[32];
    }

    private sealed class Reader(RfidEmployeeRecord? employee) : IRfidEmployeeReader
    {
        public Task<RfidEmployeeRecord?> ReadAsync(
            byte[] credentialFingerprint,
            CancellationToken cancellationToken) => Task.FromResult(employee);
    }
}
