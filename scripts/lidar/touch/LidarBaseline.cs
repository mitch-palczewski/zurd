using System;
using System.Collections.Generic;

namespace Zurd.Lidar;

/// <summary>
/// What the sensor sees with nobody touching: one reference distance per angle bin. Immutable
/// once built, so the detector and the view can share it.
/// <para>
/// Each bin keeps a low percentile of the distances seen while capturing, not the mean. At an
/// edge that flickers between a near and a far surface, a mean lands in the empty space between
/// them, where the far readings would then look like touches; the low percentile lands on the
/// near side.
/// </para>
/// </summary>
public sealed class LidarBaseline
{
    private readonly float[] _distances;

    internal LidarBaseline(float binDeg, float[] distances, int rotations)
    {
        BinDeg = binDeg;
        _distances = distances;
        Rotations = rotations;

        foreach (float d in distances)
        {
            if (!float.IsPositiveInfinity(d))
                CoveredBins++;
        }
    }

    public float BinDeg { get; }

    public int BinCount => _distances.Length;

    /// <summary>Bins where the capture saw a surface. In the others, any return counts as new.</summary>
    public int CoveredBins { get; }

    /// <summary>How many rotations the baseline was built from.</summary>
    public int Rotations { get; }

    /// <summary>Centre angle of a bin, in degrees.</summary>
    public float BinCenterDeg(int bin) => (bin + 0.5f) * BinDeg;

    /// <summary>Reference distance of a bin in millimetres, or +infinity if nothing was seen there.</summary>
    public float DistanceMm(int bin) => _distances[bin];

    public int BinOf(float angleDeg) => BinOf(angleDeg, BinDeg, BinCount);

    /// <summary>Nearest reference within <paramref name="spread"/> bins either side of <paramref name="bin"/>, wrapping at 360°.</summary>
    public float NearestAround(int bin, int spread)
    {
        float nearest = float.PositiveInfinity;
        for (int i = -spread; i <= spread; i++)
        {
            int b = ((bin + i) % BinCount + BinCount) % BinCount;
            nearest = MathF.Min(nearest, _distances[b]);
        }

        return nearest;
    }

    internal static int BinCountFor(float binDeg) => (int)MathF.Ceiling(360f / binDeg);

    internal static int BinOf(float angleDeg, float binDeg, int binCount) =>
        Math.Clamp((int)(angleDeg / binDeg), 0, binCount - 1);
}

/// <summary>
/// Collects rotations into per-bin distance lists, then reduces them to a <see cref="LidarBaseline"/>.
/// Not thread-safe; owned by <see cref="TouchDetector"/>.
/// </summary>
internal sealed class BaselineCapture
{
    private readonly float _binDeg;
    private readonly List<float>?[] _bins;

    public BaselineCapture(float binDeg, int targetRotations)
    {
        _binDeg = MathF.Max(binDeg, 0.1f);
        _bins = new List<float>?[LidarBaseline.BinCountFor(_binDeg)];
        TargetRotations = Math.Max(targetRotations, 1);
    }

    public int TargetRotations { get; }

    public int Rotations { get; private set; }

    public bool IsComplete => Rotations >= TargetRotations;

    public float Progress => Rotations / (float)TargetRotations;

    public void Add(LidarScan scan)
    {
        foreach (LidarSample s in scan.Samples)
        {
            int bin = LidarBaseline.BinOf(s.AngleDeg, _binDeg, _bins.Length);
            (_bins[bin] ??= new List<float>()).Add(s.DistanceMm);
        }

        Rotations++;
    }

    public LidarBaseline Build(float percentile)
    {
        percentile = Math.Clamp(percentile, 0f, 1f);

        var distances = new float[_bins.Length];
        for (int i = 0; i < _bins.Length; i++)
        {
            List<float>? readings = _bins[i];
            if (readings is null || readings.Count == 0)
            {
                distances[i] = float.PositiveInfinity;
                continue;
            }

            readings.Sort();
            distances[i] = readings[(int)(percentile * (readings.Count - 1))];
        }

        return new LidarBaseline(_binDeg, distances, Rotations);
    }
}
