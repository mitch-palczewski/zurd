namespace Zurd.Lidar;

public enum LidarConnectionState
{
    Disconnected,
    Connecting,
    /// <summary>Connected and the scan has been started. Says nothing about whether data is arriving.</summary>
    Streaming,
    Stopping,
    Failed,
}

public enum LidarStageState
{
    Pending,
    Ok,
    Warning,
    Failed,
}

/// <summary>One line of the status panel: a state plus a human-readable explanation.</summary>
public readonly record struct LidarStage(LidarStageState State, string Detail);

/// <summary>What the lidar told us about itself during connect.</summary>
/// <param name="HealthStatus">0 = good, 1 = warning, 2 = error, -1 = the lidar did not answer the health query.</param>
public sealed record LidarDeviceInfo(
    string ModelName,
    string Firmware,
    string Hardware,
    string Serial,
    int HealthStatus,
    int HealthErrorCode);

/// <summary>
/// Snapshot for the status panel. The three stages are deliberately independent: opening the port
/// proves little, so "data is flowing" and "the data looks right" are judged separately.
/// </summary>
public sealed record LidarStatus
{
    public LidarConnectionState State { get; init; }

    /// <summary>Stage 1: port opened and the lidar answered a GetInfo request.</summary>
    public LidarStage Connection { get; init; }

    /// <summary>Stage 2: measurements are arriving right now.</summary>
    public LidarStage Data { get; init; }

    /// <summary>Stage 3: rotation speed and point count look right, and the lidar reports no fault.</summary>
    public LidarStage Health { get; init; }

    public float PointsPerSecond { get; init; }
    public float RevolutionsPerSecond { get; init; }
    public float PointsPerRevolution { get; init; }

    /// <summary>Infinity until the first data arrives.</summary>
    public double SecondsSinceLastData { get; init; } = double.PositiveInfinity;

    public long TotalPoints { get; init; }
    public long TotalRevolutions { get; init; }

    public LidarDeviceInfo? Device { get; init; }
}
