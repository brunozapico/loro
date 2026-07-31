/// Decides when the final transcript must be placed on the system clipboard.
/// A failed cursor injection always wins over the user's automatic-copy
/// preference so the text remains recoverable with Command-V.
public enum TranscriptionDeliveryPolicy {
    public static func shouldCopy(
        automaticCopyEnabled: Bool,
        injectionSucceeded: Bool
    ) -> Bool {
        automaticCopyEnabled || !injectionSucceeded
    }
}
