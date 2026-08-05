using System.Reflection;
using Ebir.Mes.Infrastructure.Pallets;
using Xunit;

namespace Ebir.Mes.IntegrationTests.Pallets;

public sealed class SqlPalletCloserTranslationTests
{
    [Theory]
    [InlineData(51400, false)]
    [InlineData(51401, false)]
    [InlineData(51402, false)]
    [InlineData(51403, false)]
    [InlineData(51404, false)]
    [InlineData(51405, false)]
    [InlineData(51406, false)]
    [InlineData(51407, false)]
    [InlineData(51408, false)]
    [InlineData(51409, false)]
    [InlineData(51410, false)]
    [InlineData(51411, false)]
    [InlineData(55400, false)]
    [InlineData(55401, true)]
    [InlineData(55402, false)]
    [InlineData(55403, false)]
    [InlineData(55404, true)]
    public void TryTranslate_KnownError_ReturnsSafeMapping(int errorNumber, bool unavailable)
    {
        var arguments = new object?[] { errorNumber, null };
        var mapped = (bool)typeof(SqlPalletCloser).GetMethod("TryTranslate", BindingFlags.Static | BindingFlags.NonPublic)!.Invoke(null, arguments)!;
        Assert.True(mapped);
        var tuple = arguments[1]!;
        Assert.Equal(unavailable, (bool)tuple.GetType().GetField("Item3")!.GetValue(tuple)!);
        Assert.False(string.IsNullOrWhiteSpace((string)tuple.GetType().GetField("Item1")!.GetValue(tuple)!));
    }

    [Fact]
    public void TryTranslate_UnknownError_DoesNotMap()
    {
        var arguments = new object?[] { 59999, null };
        var mapped = (bool)typeof(SqlPalletCloser).GetMethod("TryTranslate", BindingFlags.Static | BindingFlags.NonPublic)!.Invoke(null, arguments)!;
        Assert.False(mapped);
    }
}
