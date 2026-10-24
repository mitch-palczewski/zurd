using RpLidar.NET.Entities;

namespace Zurd.Lidar;

/// <summary>
/// Settings for one <see cref="LidarDevice"/>. Port, baud rate, scan mode, range and batch
/// interval are read when the device connects; the health thresholds are read live.
/// </summary>
public sealed class LidarDeviceOptions
{
    /// <summary>Serial port, e.g. <c>COM3</c> or <c>/dev/ttyUSB0</c>.</summary>
    public string Port { get; set; } = "";

    /// <summary>115200 for the A1M8 and A2M8. (A2M12 and A3 use 256000.)</summary>
    public int BaudRate { get; set; } = 115200;

    /// <summary>
    /// Use Sensitivity on an A1: it is the driver's default and the mode its author tested on an
    /// A1M8. Boost is for the A2 and A3. The driver can start a Standard scan but never decodes its
    /// data, so Standard always ends in "no data".
    /// </summary>
    public ScanMode ScanMode { get; set; } = ScanMode.Sensitivity;

    /// <summary>Motor speed, 0..1023. 660 is the driver's default and gives roughly 5-6 rotations/s on an A1.</summary>
    public ushort MotorPwm { get; set; } = 660;

    /// <summary>Points farther than this are dropped by the driver. 12 m is the A1M8's rated range.</summary>
    public int MaxDistanceMm { get; set; } = 12000;

    /// <summary>
    /// How often the driver hands over a batch of points. The driver's own default is 400 ms,
    /// which is far too slow for touch; 25 ms keeps latency low without busy-looping.
    /// </summary>
    public int BatchIntervalMs { get; set; } = 25;

    // ---- Health thresholds (stage 3 of the status panel) ----

    /// <summary>Slowest rotation that still counts as healthy.</summary>
    public float MinRevolutionHz { get; set; } = 2f;

    /// <summary>Fastest rotation that still counts as healthy.</summary>
    public float MaxRevolutionHz { get; set; } = 12f;

    /// <summary>
    /// Fewest points in an average rotation that still counts as healthy. The driver drops
    /// zero-distance readings before we see them, so a low count means missing returns.
    /// </summary>
    public int MinPointsPerRevolution { get; set; } = 300;

    /// <summary>Seconds to wait for the first data after starting a scan before calling it a failure.</summary>
    public double NoDataTimeoutSec { get; set; } = 3.0;

    /// <summary>Seconds without new data, once data has flowed, before calling the stream stalled.</summary>
    public double StallTimeoutSec { get; set; } = 1.0;
}
