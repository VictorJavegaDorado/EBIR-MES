using Ebir.Mes.Application.Rfid;
using Ebir.Mes.Integrations.Rfid;
using Xunit;

namespace Ebir.Mes.Integrations.Tests.Rfid;

public sealed class HmacSha256RfidCredentialFingerprinterTests
{
    private static readonly string Key = Convert.ToBase64String(
        Enumerable.Range(1, 32).Select(value => (byte)value).ToArray());

    [Fact]
    public void Fingerprint_normalizes_separators_and_case()
    {
        var fingerprinter = new HmacSha256RfidCredentialFingerprinter(Key);

        var first = fingerprinter.Fingerprint("04-a1-b2-c3");
        var second = fingerprinter.Fingerprint("04:A1:B2:C3");

        Assert.Equal(32, first.Length);
        Assert.Equal(first, second);
    }

    [Theory]
    [InlineData("123")]
    [InlineData("04-A1-Z2-C3")]
    [InlineData("04/A1/B2/C3")]
    public void Fingerprint_rejects_invalid_identifier(string credential)
    {
        var fingerprinter = new HmacSha256RfidCredentialFingerprinter(Key);

        Assert.Throws<RfidCredentialInvalidException>(
            () => fingerprinter.Fingerprint(credential));
    }

    [Fact]
    public void Fingerprint_requires_external_lookup_key()
    {
        var fingerprinter = new HmacSha256RfidCredentialFingerprinter(null);

        Assert.Throws<RfidIdentificationUnavailableException>(
            () => fingerprinter.Fingerprint("04A1B2C3"));
    }
}
