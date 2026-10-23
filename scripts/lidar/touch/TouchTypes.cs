using System;
using System.Collections.Generic;
using Godot;

namespace Zurd.Lidar;

/// <summary>
/// A group of neighbouring foreground points from one rotation. Positions are lidar-local
/// millimetres with no angle offset or mirror (<see cref="LidarGeometry.ToLocal"/> with defaults).
/// </summary>
/// <param name="CentroidMm">Mean position of the points. The lidar only sees the near side of a
/// hand, so this sits a little in front of the hand's true centre.</param>
/// <param name="WidthMm">Distance from the first point to the last, across the blob.</param>
/// <param name="IsTouchSized">Passed the point-count and width limits, so it may become a touch.</param>
public readonly record struct TouchBlob(Vector2 CentroidMm, float WidthMm, int PointCount, bool IsTouchSized);

/// <summary>A touch-sized blob followed across rotations.</summary>
/// <param name="Id">Unique per detector once <paramref name="Confirmed"/>; 0 while still a candidate.</param>
/// <param name="Confirmed">Seen for enough rotations in a row to count as a touch.</param>
/// <param name="PositionMm">Latest centroid, lidar-local millimetres.</param>
/// <param name="StartedSec">When the blob first appeared, on the <see cref="LidarScan.TimestampSec"/> clock.</param>
/// <param name="MissedRotations">Rotations in a row it has gone unseen. Above 0 it is coasting on its last position.</param>
public readonly record struct TrackedTouch(
    int Id,
    bool Confirmed,
    Vector2 PositionMm,
    float WidthMm,
    double StartedSec,
    int MissedRotations);

public enum TouchEventKind
{
    Began,
    Ended,
}

/// <param name="TimestampSec">When the event was decided, on the <see cref="LidarScan.TimestampSec"/> clock.</param>
/// <param name="DurationSec">For Began, how long confirmation took. For Ended, how long the touch was held.</param>
public readonly record struct TouchEvent(
    TouchEventKind Kind,
    int TouchId,
    Vector2 PositionMm,
    double TimestampSec,
    double DurationSec);

/// <summary>Everything the detector concluded from one rotation. Immutable.</summary>
public sealed class TouchFrame
{
    private readonly bool[] _foreground;

    internal TouchFrame(LidarScan scan, bool[] foreground, TouchBlob[] blobs, TrackedTouch[] touches, TouchEvent[] events)
    {
        Scan = scan;
        _foreground = foreground;
        Blobs = blobs;
        Touches = touches;
        Events = events;

        foreach (TrackedTouch touch in touches)
        {
            if (touch.Confirmed)
                ConfirmedCount++;
        }
    }

    /// <summary>A frame with nothing detected, for when there is no baseline to compare against.</summary>
    internal static TouchFrame Empty(LidarScan scan) => new(
        scan,
        new bool[scan.Count],
        Array.Empty<TouchBlob>(),
        Array.Empty<TrackedTouch>(),
        Array.Empty<TouchEvent>());

    public LidarScan Scan { get; }

    /// <summary>One flag per sample of <see cref="Scan"/>, true where the sample came closer than the baseline.</summary>
    public ReadOnlySpan<bool> Foreground => _foreground;

    /// <summary>Every blob this rotation, including ones too small or too wide to be touches.</summary>
    public IReadOnlyList<TouchBlob> Blobs { get; }

    /// <summary>Candidates and confirmed touches, including ones coasting through a missed rotation.</summary>
    public IReadOnlyList<TrackedTouch> Touches { get; }

    /// <summary>How many of <see cref="Touches"/> are confirmed.</summary>
    public int ConfirmedCount { get; }

    /// <summary>Touches that began or ended this rotation.</summary>
    public IReadOnlyList<TouchEvent> Events { get; }
}
