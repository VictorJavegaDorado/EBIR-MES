using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Ebir.Mes.Application.ProductionDashboard;
using Ebir.Mes.Application.ProductionOrders;
using Ebir.Mes.Application.ProductionWorkstations;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Xunit;

namespace Ebir.Mes.IntegrationTests.ProductionDashboard;

public sealed class ProductionDashboardEndpointTests
{
    [Fact]
    public async Task Dashboard_ReturnsActiveAndFreeLinesInOneSnapshot()
    {
        var now = new DateTime(2026, 9, 4, 10, 0, 0, DateTimeKind.Utc);
        var order = new ProductionOrderSelectionRecord(
            36, "FL26-00008", "27920LG", "Producto piloto", "LOTE-08",
            100, 60, 20, 0, 10m, "ABIERTA", now.AddHours(-1));
        var table = new ProductionTableStateRecord(
            40, 36, 1, "PRODUCIENDO", now.AddMinutes(-30), now, 1800, 2,
            12m, "POK", 20,
            [new(7, "EMP-7", "Operario piloto", now.AddMinutes(-30), 1800, "PRODUCIENDO")]);
        var snapshot = new ProductionDashboardSnapshotRecord(now,
        [
            new(1, "LINEA-01", "Linea uno", "CT-01", "Fabricacion",
                "PRODUCIENDO", null, now, order, table, 3,
                "CONFIRMADA", "IMPRESA", 0, 0, 0, 0, 55m, 3600, "412", "Ana Perez"),
            new(2, "LINEA-02", "Linea dos", "CT-01", "Fabricacion",
                "LIBRE", null, now, null, null, 0,
                null, null, 0, 0, 0, 0, 0m)
        ]);
        using var factory = CreateFactory(new StubReader(snapshot));
        using var client = factory.CreateClient();

        using var response = await client.GetAsync("/api/production-dashboard");
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(now, body.RootElement.GetProperty("serverTimeUtc").GetDateTime());
        var lines = body.RootElement.GetProperty("lines").EnumerateArray().ToArray();
        Assert.Equal(2, lines.Length);
        Assert.Equal("FL26-00008", lines[0].GetProperty("order")
            .GetProperty("orderNumber").GetString());
        Assert.Equal(60, lines[0].GetProperty("order")
            .GetProperty("goodQuantity").GetInt32());
        Assert.Single(lines[0].GetProperty("table")
            .GetProperty("operators").EnumerateArray());
        Assert.Equal(55m, lines[0].GetProperty("theoreticalUnitsToDate").GetDecimal());
        Assert.Equal(3600, lines[0].GetProperty("resourceSeconds").GetInt64());
        Assert.Equal("412", lines[0].GetProperty("supervisorNavEmployeeCode").GetString());
        Assert.Equal(JsonValueKind.Null, lines[1].GetProperty("order").ValueKind);
        Assert.Equal(JsonValueKind.Null, lines[1].GetProperty("supervisorNavEmployeeCode").ValueKind);
    }

    [Fact]
    public async Task Dashboard_FiltersBySupervisorAndReturnsTheSupervisor()
    {
        var now = new DateTime(2026, 9, 14, 10, 0, 0, DateTimeKind.Utc);
        var supervisor = new ProductionDashboardSupervisorRecord(
            "412", "Ana Perez", [new(1, "LINEA-01", "Linea uno")]);
        var snapshot = new ProductionDashboardSnapshotRecord(now,
        [
            new(1, "LINEA-01", "Linea uno", "CT-01", "Fabricacion",
                "LIBRE", null, now, null, null, 0,
                null, null, 0, 0, 0, 0, 0m, 0, "412", "Ana Perez")
        ], supervisor);
        var reader = new StubReader(snapshot);
        using var factory = CreateFactory(reader);
        using var client = factory.CreateClient();

        using var response = await client.GetAsync("/api/production-dashboard?supervisor=412");
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("412", reader.LastSupervisorCode);
        Assert.Equal("Ana Perez", body.RootElement.GetProperty("supervisor")
            .GetProperty("fullName").GetString());
        Assert.Single(body.RootElement.GetProperty("lines").EnumerateArray());
    }

    [Fact]
    public async Task Dashboard_RejectsAnOversizedSupervisorCode()
    {
        using var factory = CreateFactory(new StubReader(
            new ProductionDashboardSnapshotRecord(DateTime.UtcNow, [])));
        using var client = factory.CreateClient();

        using var response = await client.GetAsync(
            "/api/production-dashboard?supervisor=" + new string('9', 31));
        var text = await response.Content.ReadAsStringAsync();

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Contains("PRODUCTION_DASHBOARD_SUPERVISOR_INVALID", text);
    }

    [Fact]
    public async Task Supervisors_ReturnsAssignedLinesPerSupervisor()
    {
        var reader = new StubReader(
            new ProductionDashboardSnapshotRecord(DateTime.UtcNow, []),
            [
                new("412", "Ana Perez",
                    [new(1, "LINEA-01", "Linea uno"), new(2, "LINEA-02", "Linea dos")]),
                new("577", "Luis Gil", [new(3, "LINEA-03", "Linea tres")])
            ]);
        using var factory = CreateFactory(reader);
        using var client = factory.CreateClient();

        using var response = await client.GetAsync("/api/production-dashboard/supervisors");
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var supervisors = body.RootElement.EnumerateArray().ToArray();
        Assert.Equal(2, supervisors.Length);
        Assert.Equal("412", supervisors[0].GetProperty("navEmployeeCode").GetString());
        Assert.Equal(2, supervisors[0].GetProperty("lines").GetArrayLength());
        Assert.Equal("LINEA-03", supervisors[1].GetProperty("lines")[0]
            .GetProperty("lineCode").GetString());
    }

    [Fact]
    public async Task Dashboard_HidesInfrastructureFailure()
    {
        using var factory = CreateFactory(new UnavailableReader());
        using var client = factory.CreateClient();

        using var response = await client.GetAsync("/api/production-dashboard");
        var text = await response.Content.ReadAsStringAsync();

        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        Assert.Contains("PRODUCTION_DASHBOARD_UNAVAILABLE", text);
        Assert.DoesNotContain("synthetic database detail", text);
    }

    [Fact]
    public async Task LineAssignments_ReturnsAllLinesWithTheirCurrentSupervisor()
    {
        var reader = new StubReader(
            new ProductionDashboardSnapshotRecord(DateTime.UtcNow, []),
            lineOptions:
            [
                new(1, "LINEA-01", "Linea uno", "CT-01", "Fabricacion", "412", "Ana Perez"),
                new(2, "LINEA-02", "Linea dos", "CT-01", "Fabricacion", null, null)
            ]);
        using var factory = CreateFactory(reader);
        using var client = factory.CreateClient();

        using var response = await client.GetAsync("/api/production-dashboard/line-assignments");
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var lines = body.RootElement.EnumerateArray().ToArray();
        Assert.Equal(2, lines.Length);
        Assert.Equal("412", lines[0].GetProperty("supervisorNavEmployeeCode").GetString());
        Assert.Equal(JsonValueKind.Null, lines[1].GetProperty("supervisorNavEmployeeCode").ValueKind);
    }

    [Fact]
    public async Task SetLineAssignments_SavesAndReturnsTheRefreshedList()
    {
        var reader = new StubReader(
            new ProductionDashboardSnapshotRecord(DateTime.UtcNow, []),
            lineOptions: [new(1, "LINEA-01", "Linea uno", "CT-01", "Fabricacion", "412", "Ana Perez")]);
        var writer = new StubWriter();
        using var factory = CreateFactory(reader, writer);
        using var client = factory.CreateClient();

        using var response = await client.PostAsJsonAsync(
            "/api/production-dashboard/line-assignments",
            new { employeeId = 55, lineIds = new long[] { 1, 2 } });
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(55, writer.LastEmployeeId);
        Assert.Equal([1, 2], writer.LastLineIds);
        Assert.Single(body.RootElement.EnumerateArray());
    }

    [Fact]
    public async Task SetLineAssignments_RejectsALockedLineWithConflict()
    {
        var writer = new StubWriter(
            new LineSupervisorAssignmentRejectedException(
                "LINE_ASSIGNMENT_LOCKED", "synthetic conflict"));
        using var factory = CreateFactory(
            new StubReader(new ProductionDashboardSnapshotRecord(DateTime.UtcNow, [])), writer);
        using var client = factory.CreateClient();

        using var response = await client.PostAsJsonAsync(
            "/api/production-dashboard/line-assignments",
            new { employeeId = 55, lineIds = new long[] { 1 } });
        var text = await response.Content.ReadAsStringAsync();

        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
        Assert.Contains("LINE_ASSIGNMENT_LOCKED", text);
    }

    [Fact]
    public async Task SetLineAssignments_RejectsAnEmployeeWithoutSupervisorRole()
    {
        var writer = new StubWriter(
            new LineSupervisorAssignmentRejectedException(
                "EMPLOYEE_NOT_ACTIVE_SUPERVISOR", "synthetic role"));
        using var factory = CreateFactory(
            new StubReader(new ProductionDashboardSnapshotRecord(DateTime.UtcNow, [])), writer);
        using var client = factory.CreateClient();

        using var response = await client.PostAsJsonAsync(
            "/api/production-dashboard/line-assignments",
            new { employeeId = 55, lineIds = new long[] { 1 } });
        var text = await response.Content.ReadAsStringAsync();

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
        Assert.Contains("EMPLOYEE_NOT_ACTIVE_SUPERVISOR", text);
    }

    [Fact]
    public async Task SetLineAssignments_RejectsAnInvalidEmployeeId()
    {
        var writer = new StubWriter();
        using var factory = CreateFactory(
            new StubReader(new ProductionDashboardSnapshotRecord(DateTime.UtcNow, [])), writer);
        using var client = factory.CreateClient();

        using var response = await client.PostAsJsonAsync(
            "/api/production-dashboard/line-assignments",
            new { employeeId = 0, lineIds = Array.Empty<long>() });
        var text = await response.Content.ReadAsStringAsync();

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Contains("LINE_ASSIGNMENT_REQUEST_INVALID", text);
        Assert.False(writer.Called);
    }

    private static WebApplicationFactory<Program> CreateFactory(
        IProductionDashboardReader reader,
        ILineSupervisorAssignmentWriter? writer = null) =>
        new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
            builder.ConfigureTestServices(services =>
            {
                services.RemoveAll<IProductionDashboardReader>();
                services.AddSingleton(reader);
                services.RemoveAll<ILineSupervisorAssignmentWriter>();
                services.AddSingleton(writer ?? new StubWriter());
            }));

    private sealed class StubReader(
        ProductionDashboardSnapshotRecord snapshot,
        IReadOnlyList<ProductionDashboardSupervisorRecord>? supervisors = null,
        IReadOnlyList<LineAssignmentOptionRecord>? lineOptions = null)
        : IProductionDashboardReader
    {
        public string? LastSupervisorCode { get; private set; }

        public Task<ProductionDashboardSnapshotRecord> ReadAsync(
            string? supervisorNavEmployeeCode,
            CancellationToken cancellationToken)
        {
            LastSupervisorCode = supervisorNavEmployeeCode;
            return Task.FromResult(snapshot);
        }

        public Task<IReadOnlyList<ProductionDashboardSupervisorRecord>> ReadSupervisorsAsync(
            CancellationToken cancellationToken) =>
            Task.FromResult(supervisors ?? Array.Empty<ProductionDashboardSupervisorRecord>());

        public Task<IReadOnlyList<LineAssignmentOptionRecord>> ReadLineAssignmentOptionsAsync(
            CancellationToken cancellationToken) =>
            Task.FromResult(lineOptions ?? Array.Empty<LineAssignmentOptionRecord>());
    }

    private sealed class UnavailableReader : IProductionDashboardReader
    {
        public Task<ProductionDashboardSnapshotRecord> ReadAsync(
            string? supervisorNavEmployeeCode,
            CancellationToken cancellationToken) =>
            throw new ProductionDashboardUnavailableException("synthetic database detail");

        public Task<IReadOnlyList<ProductionDashboardSupervisorRecord>> ReadSupervisorsAsync(
            CancellationToken cancellationToken) =>
            throw new ProductionDashboardUnavailableException("synthetic database detail");

        public Task<IReadOnlyList<LineAssignmentOptionRecord>> ReadLineAssignmentOptionsAsync(
            CancellationToken cancellationToken) =>
            throw new ProductionDashboardUnavailableException("synthetic database detail");
    }

    private sealed class StubWriter(Exception? failure = null) : ILineSupervisorAssignmentWriter
    {
        public bool Called { get; private set; }
        public long LastEmployeeId { get; private set; }
        public IReadOnlyCollection<long> LastLineIds { get; private set; } = Array.Empty<long>();

        public Task SetAsync(
            long supervisorEmployeeId,
            IReadOnlyCollection<long> lineIds,
            CancellationToken cancellationToken)
        {
            Called = true;
            LastEmployeeId = supervisorEmployeeId;
            LastLineIds = lineIds;
            if (failure is not null) throw failure;
            return Task.CompletedTask;
        }
    }
}
