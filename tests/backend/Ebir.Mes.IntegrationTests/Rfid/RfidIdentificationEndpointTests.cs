using System.Net;
using System.Net.Http.Json;
using Ebir.Mes.Application.Rfid;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Xunit;

namespace Ebir.Mes.IntegrationTests.Rfid;

public sealed class RfidIdentificationEndpointTests
{
    [Fact]
    public async Task IdentifyAsync_returns_active_employee_without_echoing_credential()
    {
        using var factory = Factory(new StubReader(new(4, "EMP-04", "Operario Test")));
        using var response = await factory.CreateClient().PostAsJsonAsync(
            "/api/operator-identification/rfid",
            new { credential = "04A1B2C3" });
        var content = await response.Content.ReadAsStringAsync();

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Contains("EMP-04", content);
        Assert.DoesNotContain("04A1B2C3", content);
    }

    [Fact]
    public async Task IdentifyAsync_returns_not_found_without_exposing_fingerprint()
    {
        using var factory = Factory(new StubReader(null));
        using var response = await factory.CreateClient().PostAsJsonAsync(
            "/api/operator-identification/rfid",
            new { credential = "04A1B2C3" });
        var content = await response.Content.ReadAsStringAsync();

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        Assert.Contains("RFID_CREDENTIAL_NOT_FOUND", content);
        Assert.DoesNotContain("04A1B2C3", content);
    }

    private static WebApplicationFactory<Program> Factory(IRfidEmployeeReader reader) =>
        new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
        {
            builder.UseEnvironment("Testing");
            builder.ConfigureTestServices(services =>
            {
                services.RemoveAll<IRfidCredentialFingerprinter>();
                services.RemoveAll<IRfidEmployeeReader>();
                services.AddSingleton<IRfidCredentialFingerprinter>(
                    new StubFingerprinter());
                services.AddSingleton(reader);
            });
        });

    private sealed class StubFingerprinter : IRfidCredentialFingerprinter
    {
        public byte[] Fingerprint(string rawCredential) => new byte[32];
    }

    private sealed class StubReader(RfidEmployeeRecord? employee) : IRfidEmployeeReader
    {
        public Task<RfidEmployeeRecord?> ReadAsync(
            byte[] credentialFingerprint,
            CancellationToken cancellationToken) => Task.FromResult(employee);
    }
}
