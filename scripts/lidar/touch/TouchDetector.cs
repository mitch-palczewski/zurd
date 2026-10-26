using System;
using System.Collections.Generic;
using Godot;

namespace Zurd.Lidar;

/// <summary>
/// Finds touches in one lidar's scans. Each rotation is compared with a captured
/// <see cref="LidarBaseline"/>; points that came closer are grouped into blobs; touch-sized blobs
/// are followed across rotations so each touch gets an id, one Began event and one Ended event.
/// <para>
/// Plain C#, main thread only: pass it every new <see cref="LidarScan"/> from
/// <see cref="LidarDevice.TryGetNewScan"/>. Positions are lidar-local millimetres with no angle
/// offset or mirror; mapping them onto the wall is calibration's job.
/// </para>
/// </summary>
public sealed class TouchDetector
{
    private readonly TouchTracker _tracker = new();
    private BaselineCapture? _capture;

    public TouchDetector(TouchDetectorOptions options)
    {
        Options = options;
    }

    public TouchDetectorOptions Options { get; }

    /// <summary>The reference that detection compares against, or null if none has been captured.</summary>
    public LidarBaseline? Baseline { get; private set; }

    /// <summary>
    /// Optional convex polygon in lidar-local millimetres. When set, only points inside it can become
    /// foreground, so nothing outside the wall's projected image is ever a touch. Calibration sets
    /// it (see <see cref="WallCalibration.TryGetArea"/>); null means everywhere within range.
    /// </summary>
    public IReadOnlyList<Vector2>? DetectionArea { get; set; }

    public bool IsCapturingBaseline => _capture is not null;

    /// <summary>0..1 while a capture runs.</summary>
    public float BaselineProgress => _capture?.Progress ?? 0f;

    /// <summary>
    /// Records the next <see cref="TouchDetectorOptions.BaselineRotations"/> rotations as the new
    /// baseline. The scan plane must stay clear meanwhile. Nothing is detected until it finishes.
    /// </summary>
    public void BeginBaselineCapture()
    {
        _capture = new BaselineCapture(Options.BaselineBinDeg, Options.BaselineRotations);
        _tracker.Reset();
    }

    public void CancelBaselineCapture() => _capture = null;

    public void ClearBaseline()
    {
        _capture = null;
        Baseline = null;
        _tracker.Reset();
    }

    /// <summary>Forgets touches in progress without reporting them as ended, e.g. after a disconnect.</summary>
    public void ResetTracking() => _tracker.Reset();

    public TouchFrame Process(LidarScan scan)
    {
        if (_capture is not null)
        {
            _capture.Add(scan);
            if (_capture.IsComplete)
            {
                Baseline = _capture.Build(Options.BaselinePercentile);
                _capture = null;
            }

            return TouchFrame.Empty(scan);
        }

        if (Baseline is null)
            return TouchFrame.Empty(scan);

        bool[] foreground = MarkForeground(scan, Baseline);
        TouchBlob[] blobs = FindBlobs(scan, foreground);

        var touches = new List<TrackedTouch>();
        var events = new List<TouchEvent>();
        _tracker.Update(blobs, scan.TimestampSec, Options, touches, events);

        return new TouchFrame(scan, foreground, blobs, touches.ToArray(), events.ToArray());
    }

    private bool[] MarkForeground(LidarScan scan, LidarBaseline baseline)
    {
        TouchDetectorOptions opt = Options;
        IReadOnlyList<Vector2>? area = DetectionArea;
        ReadOnlySpan<LidarSample> samples = scan.Samples;
        var foreground = new bool[samples.Length];

        for (int i = 0; i < samples.Length; i++)
        {
            LidarSample s = samples[i];
            if (s.DistanceMm < opt.MinRangeMm || s.DistanceMm > opt.MaxRangeMm)
                continue;

            if (area is not null && !LidarGeometry.IsInsideConvex(LidarGeometry.ToLocal(s.AngleDeg, s.DistanceMm), area))
                continue;

            float reference = baseline.NearestAround(baseline.BinOf(s.AngleDeg), opt.BaselineSpreadBins);
            if (float.IsPositiveInfinity(reference))
            {
                // Nothing was here during the capture, so anything in range is new.
                foreground[i] = true;
                continue;
            }

            float margin = MathF.Max(opt.MinDepthChangeMm, reference * opt.RelativeDepthChange);
            foreground[i] = s.DistanceMm < reference - margin;
        }

        return foreground;
    }

    private TouchBlob[] FindBlobs(LidarScan scan, bool[] foreground)
    {
        // Samples are sorted by angle, and a single sensor can't see one object behind another, so
        // walking the sweep and splitting wherever consecutive foreground points jump apart is enough.
        TouchDetectorOptions opt = Options;
        ReadOnlySpan<LidarSample> samples = scan.Samples;
        var clusters = new List<List<Vector2>>();
        List<Vector2>? current = null;

        for (int i = 0; i < samples.Length; i++)
        {
            if (!foreground[i])
                continue;

            Vector2 p = LidarGeometry.ToLocal(samples[i].AngleDeg, samples[i].DistanceMm);
            if (current is null || p.DistanceTo(current[^1]) > opt.ClusterGapMm)
            {
                current = new List<Vector2>();
                clusters.Add(current);
            }

            current.Add(p);
        }

        // The sweep is a circle: a blob straddling 0° arrives as a tail cluster plus a head cluster.
        if (clusters.Count >= 2 && clusters[^1][^1].DistanceTo(clusters[0][0]) <= opt.ClusterGapMm)
        {
            clusters[^1].AddRange(clusters[0]);
            clusters.RemoveAt(0);
        }

        var blobs = new TouchBlob[clusters.Count];
        for (int c = 0; c < clusters.Count; c++)
        {
            List<Vector2> points = clusters[c];

            Vector2 sum = Vector2.Zero;
            foreach (Vector2 p in points)
                sum += p;

            float width = points[0].DistanceTo(points[^1]);
            bool touchSized = points.Count >= opt.MinPointsPerBlob && width <= opt.MaxBlobWidthMm;
            blobs[c] = new TouchBlob(sum / points.Count, width, points.Count, touchSized);
        }

        return blobs;
    }
}
