/// Delta de una conciliación: conteo físico − stock teórico previo.
public enum StockRules {
    public static func reconciliationDelta(counted: Int, theoretical: Int) -> Int {
        counted - theoretical
    }

    /// Stock operativo local: último snapshot del servidor ajustado por mutaciones pendientes.
    public static func localOperationalStock(
        serverOperational: Int,
        pendingSoldUnits: Int,
        pendingReconciledCount: Int?
    ) -> Int {
        if let pendingReconciledCount {
            return max(pendingReconciledCount - pendingSoldUnits, 0)
        }
        return max(serverOperational - pendingSoldUnits, 0)
    }
}
