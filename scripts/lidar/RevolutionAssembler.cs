using System;
using System.Collections.Generic;
using RpLidar.NET.Entities;

namespace Zurd.Lidar;

/// <summary>
/// Stitches the driver's timed batches of points back into whole rotations.
/// <para>
/// A rotation ends when the angle wraps (for example 359° followed by 1°). The driver's
/// <c>StartFlag</c> would be the obvious marker, but a wrap still shows up when the packet carrying
/// the flag is lost (a checksum error, a USB hiccup), and it is immune to the small out-of-order
/// angles the express-mode decoder can produce near the seam.
/// </para>
/// Not thread-safe: call <see cref="Add"/> from one thread only (the driver's scan thread).
/// </summary>
internal sealed class RevolutionAssembler
{
    /// <summary>A drop of more than this between consecutive angles is a wrap, not jitter.</summary>
    private const float WrapDropDeg = 180f;

    /// <summary>Anything shorter than this is a partial rotation or seam jitter, not a scan.</summary>
    private const int MinSamplesPerRevolution = 50;

    private static readonly Comparison<LidarSample> ByAngle =
        (a, b) => a.AngleDeg.CompareTo(b.AngleDeg);

    private readonly Action<LidarSample[]> _onRevolution;
    private readonly List<LidarSample> _current = new(2048);
    private float _lastAngle = float.NaN;
    private bool _seenSeam;

    public RevolutionAssembler(Action<LidarSample[]> onRevolution)
    {
        _onRevolution = onRevolution;
    }

    public void Add(List<LidarPoint> batch)
    {
        for (int i = 0; i < batch.Count; i++)
        {
            LidarPoint p = batch[i];

            float angle = p.Angle % 360f;
            if (angle < 0f)
                angle += 360f;

            if (!float.IsNaN(_lastAngle) && _lastAngle - angle > WrapDropDeg)
            {
                // The first partial rotation (we joined mid-sweep) is thrown away.
                if (_seenSeam && _current.Count >= MinSamplesPerRevolution)
                    Emit();

                _current.Clear();
                _seenSeam = true;
            }

            _current.Add(new LidarSample(angle, p.Distance, p.Quality));
            _lastAngle = angle;
        }
    }

    private void Emit()
    {
        LidarSample[] samples = _current.ToArray();
        Array.Sort(samples, ByAngle);
        _onRevolution(samples);
    }
}
