namespace Ebir.Mes.Application.Rfid;

public interface IRfidCredentialFingerprinter
{
    byte[] Fingerprint(string rawCredential);
}
