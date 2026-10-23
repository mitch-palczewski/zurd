using System;

namespace Zurd.Lidar;

/// <summary>
/// One full rotation of the sensor, sorted by angle. Immutable once published, so it can be
/// read from any thread without locking.
/// </summary>
public sealed class LidarScan
{
    private readonly LidarSample[] _samples;

    public LidarScan(long sequence, double timestampSec, LidarSample[] samples)
    {
        Sequence = sequence;
        TimestampSec = timestampSec;
        _samples = samples;
    }

    /// <summary>Increases by one for every rotation the device publishes. Never resets.</summary>
    public long Sequence { get; }

    /// <summary>Monotonic time (seconds) at which the rotation finished.</summary>
    public double TimestampSec { get; }

    public int Count => _samples.Length;

    /// <summary>The samples, ascending by <see cref="LidarSample.AngleDeg"/>. Do not modify.</summary>
    public ReadOnlySpan<LidarSample> Samples => _samples;

    public LidarSample this[int index] => _samples[index];
}
