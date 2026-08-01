using System.Security.Cryptography;
using Ebir.Mes.Application.Rfid;

namespace Ebir.Mes.Integrations.Rfid;

public sealed class HmacSha256RfidCredentialFingerprinter(string? base64Key)
    : IRfidCredentialFingerprinter
{
    public byte[] Fingerprint(string rawCredential)
    {
        var normalized = Normalize(rawCredential);
        byte[] key;
        try
        {
            key = Convert.FromBase64String(base64Key ?? string.Empty);
        }
        catch (FormatException exception)
        {
            throw new RfidIdentificationUnavailableException(
                "La clave de búsqueda RFID no tiene un formato válido.", exception);
        }
        if (key.Length < 32)
            throw new RfidIdentificationUnavailableException(
                "La clave de búsqueda RFID no está configurada.");
        try
        {
            using var hmac = new HMACSHA256(key);
            return hmac.ComputeHash(Convert.FromHexString(normalized));
        }
        finally
        {
            CryptographicOperations.ZeroMemory(key);
        }
    }

    private static string Normalize(string rawCredential)
    {
        var normalized = new string(rawCredential
            .Where(character => !char.IsWhiteSpace(character) && character is not '-' and not ':')
            .ToArray())
            .ToUpperInvariant();
        if (normalized.Length is < 8 or > 128 || normalized.Length % 2 != 0 ||
            normalized.Any(character => !Uri.IsHexDigit(character)))
        {
            throw new RfidCredentialInvalidException(
                "La credencial RFID no tiene un formato hexadecimal válido.");
        }
        return normalized;
    }
}
