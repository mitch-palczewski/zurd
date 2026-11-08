using System;
using System.Collections.Generic;
using Godot;

namespace Zurd.Lidar;

/// <summary>
/// Waits for one new touch to be held still for a few rotations, then reports where it was on
/// average. Only touches that begin after the last <see cref="Restart"/> count, so a hand that was
/// already down, or something in the scan plane that the baseline missed, is ignored rather than
/// taken for a deliberate touch.
/// <para>
/// Plain C#, main thread only: pass it every <see cref="TouchFrame"/>. Used for the calibration
/// targets and for touch buttons on the wall.
/// </para>
/// </summary>
public sealed class TouchHold
{
    private readonly List<Vector2> _samples = new();
    private int _touchId;
    private double _newSinceSec = double.NaN;
    private double _lastFrameSec = double.NaN;

    /// <summary>Rotations a touch must be held still. 6 is about a second on an A1.</summary>
    public int Rotations { get; set; } = 6;

    /// <summary>How far a held touch may wander from its average and still count as still.</summary>
    public float ToleranceMm { get; set; } = 20f;

    /// <summary>
    /// The same allowance as a fraction of the touch's distance from the sensor; the larger of the
    /// two wins. The lidar's error grows with range, so a far touch jitters more.
    /// </summary>
    public float ToleranceFraction { get; set; } = 0.01f;

    /// <summary>0..1 while a touch is being held.</summary>
    public float Progress => _samples.Count / (float)Rotations;

    public bool IsHolding => _samples.Count > 0;

    /// <summary>Average position of the touch being held, lidar-local millimetres; zero when none is.</summary>
    public Vector2 PositionMm => _samples.Count == 0 ? Vector2.Zero : Mean();

    /// <summary>New touches in the last rotation. More than one means nothing can be held.</summary>
    public int NewTouches { get; private set; }

    /// <summary>Touches in the last rotation that didn't count: down since before the last restart, or refused by the filter.</summary>
    public int IgnoredTouches { get; private set; }

    /// <summary>Drops the hold. Touches that are down now stop counting until they lift and touch again.</summary>
    public void Restart()
    {
        _samples.Clear();
        _touchId = 0;
        _newSinceSec = _lastFrameSec;
    }

    /// <summary>
    /// Feeds one rotation. Returns true on the rotation the hold completes, with the touch's id and
    /// average position; the hold then restarts, so that touch must lift before it counts again.
    /// </summary>
    /// <param name="accept">Optional filter on a touch's position; touches it refuses are ignored.</param>
    public bool Update(TouchFrame frame, out int touchId, out Vector2 positionMm, Func<Vector2, bool>? accept = null)
    {
        touchId = 0;
        positionMm = Vector2.Zero;

        _lastFrameSec = frame.Scan.TimestampSec;
        // Before the first rotation there is no "now" to count from, so whatever is down then is old.
        if (double.IsNaN(_newSinceSec))
            _newSinceSec = _lastFrameSec;

        TrackedTouch touch = default;
        int newTouches = 0;
        int ignored = 0;
        foreach (TrackedTouch t in frame.Touches)
        {
            if (!t.Confirmed)
                continue;

            if (t.StartedSec <= _newSinceSec || (accept is not null && !accept(t.PositionMm)))
            {
                ignored++;
                continue;
            }

            newTouches++;
            touch = t;
        }

        NewTouches = newTouches;
        IgnoredTouches = ignored;

        if (newTouches != 1)
        {
            _samples.Clear();
            _touchId = 0;
            return false;
        }

        // Coasting through a missed rotation: no fresh position, but not a reason to start over.
        if (touch.MissedRotations > 0)
            return false;

        // A different hand, or the same one drifting: start the hold again from here.
        float tolerance = MathF.Max(ToleranceMm, touch.PositionMm.Length() * ToleranceFraction);
        if (touch.Id != _touchId || (_samples.Count > 0 && touch.PositionMm.DistanceTo(Mean()) > tolerance))
        {
            _samples.Clear();
            _touchId = touch.Id;
        }

        _samples.Add(touch.PositionMm);
        if (_samples.Count < Rotations)
            return false;

        touchId = touch.Id;
        positionMm = Mean();
        Restart();
        return true;
    }

    private Vector2 Mean()
    {
        Vector2 sum = Vector2.Zero;
        foreach (Vector2 p in _samples)
            sum += p;
        return sum / _samples.Count;
    }
}
