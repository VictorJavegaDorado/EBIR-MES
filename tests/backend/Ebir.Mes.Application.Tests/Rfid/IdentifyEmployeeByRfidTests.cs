using Ebir.Mes.Application.Rfid;
using Xunit;

namespace Ebir.Mes.Application.Tests.Rfid;

public sealed class IdentifyEmployeeByRfidTests
{
    [Fact]
    public async Task ExecuteAsync_resolves_only_the_fingerprint()
    {
        var reader = new StubReader(new(4, "EMP-04", "Operario Test"));
        var result = await new IdentifyEmployeeByRfid(
            new StubFingerprinter(), reader)
            .ExecuteAsync("04-A1-B2-C3", CancellationToken.None);

        Assert.Equal(IdentifyEmployeeByRfidOutcome.Identified, result.Outcome);
        Assert.Equal("EMP-04", result.Employee?.NavEmployeeCode);
        Assert.Equal(32, reader.ReceivedFingerprint?.Length);
    }

    [Fact]
    public async Task ExecuteAsync_rejects_empty_credential_without_lookup()
    {
        var reader = new StubReader(null);
        var result = await new IdentifyEmployeeByRfid(
            new StubFingerprinter(), reader)
            .ExecuteAsync(" ", CancellationToken.None);

        Assert.Equal(IdentifyEmployeeByRfidOutcome.InvalidCredential, result.Outcome);
        Assert.Null(reader.ReceivedFingerprint);
    }

    private sealed class StubFingerprinter : IRfidCredentialFingerprinter
    {
        public byte[] Fingerprint(string rawCredential) => new byte[32];
    }

    private sealed class StubReader(RfidEmployeeRecord? employee) : IRfidEmployeeReader
    {
        public byte[]? ReceivedFingerprint { get; private set; }

        public Task<RfidEmployeeRecord?> ReadAsync(
            byte[] credentialFingerprint,
            CancellationToken cancellationToken)
        {
            ReceivedFingerprint = credentialFingerprint;
            return Task.FromResult(employee);
        }
    }
}
