using System.Collections.Generic;
using Godot;

namespace Zurd.Lidar;

public enum CalibrationStep
{
    /// <summary>Waiting for exactly one hand on the current target.</summary>
    WaitingForTouch,

    /// <summary>One steady touch; counting rotations until it has been held long enough.</summary>
    Holding,

    /// <summary>The target was captured; waiting for the hand to leave before the next one.</summary>
    WaitingForRelease,

    /// <summary>All targets captured; <see cref="CalibrationWizard.Points"/> is ready to solve.</summary>
    Finished,
}

/// <summary>
/// Walks through the calibration targets: corners TL, TR, BR, BL (inset from the image edges), then
/// the centre. For each, it waits for exactly one confirmed touch, averages it once it has been held
/// steady for <see cref="HoldRotations"/> rotations, then waits for the hand to leave.
/// <para>
/// Plain C#, main thread only: pass it every <see cref="TouchFrame"/> while it runs. Corners are
/// inset because a hand next to a baseline surface (the wall's frame, a side wall) isn't detected.
/// </para>
/// </summary>
public sealed class CalibrationWizard
{
    public static readonly string[] TargetNames = { "top-left", "top-right", "bottom-right", "bottom-left", "centre" };

    private readonly List<Vector2> _holdSamples = new();
    private readonly List<CalibrationPoint> _points = new();
    private int _holdTouchId;

    /// <param name="targetInset">How far the corner targets sit in from the image edges, as a fraction of the image.</param>
    public CalibrationWizard(float targetInset = 0.1f)
    {
        float lo = targetInset;
        float hi = 1f - targetInset;
        TargetsUv = new[] { new Vector2(lo, lo), new Vector2(hi, lo), new Vector2(hi, hi), new Vector2(lo, hi), new Vector2(0.5f, 0.5f) };
    }

    /// <summary>Rotations a touch must be held steady. 6 is about a second on an A1.</summary>
    public int HoldRotations { get; init; } = 6;

    /// <summary>How far a held touch may wander from its average and still count as steady.</summary>
    public float HoldToleranceMm { get; init; } = 20f;

    public IReadOnlyList<Vector2> TargetsUv { get; }

    public CalibrationStep Step { get; private set; } = CalibrationStep.WaitingForTouch;

    /// <summary>Index into <see cref="TargetsUv"/> of the target being captured; equals the target count once finished.</summary>
    public int CurrentTarget => _points.Count;

    /// <summary>0..1 while holding.</summary>
    public float HoldProgress => _holdSamples.Count / (float)HoldRotations;

    /// <summary>The last rotation had more than one confirmed touch, so nothing could be captured.</summary>
    public bool TooManyTouches { get; private set; }

    /// <summary>Captured so far, in target order. Complete once <see cref="Step"/> is Finished.</summary>
    public IReadOnlyList<CalibrationPoint> Points => _points;

    public void Update(TouchFrame frame)
    {
        if (Step == CalibrationStep.Finished)
            return;

        if (Step == CalibrationStep.WaitingForRelease)
        {
            if (frame.ConfirmedCount == 0)
                Step = _points.Count == TargetsUv.Count ? CalibrationStep.Finished : CalibrationStep.WaitingForTouch;
            return;
        }

        TooManyTouches = frame.ConfirmedCount > 1;
        if (frame.ConfirmedCount != 1)
        {
            ResetHold();
            return;
        }

        TrackedTouch touch = default;
        foreach (TrackedTouch t in frame.Touches)
        {
            if (t.Confirmed)
                touch = t;
        }

        // Coasting through a missed rotation: no fresh position, but not a reason to start over.
        if (touch.MissedRotations > 0)
            return;

        // A different hand, or the same one drifting: start the hold again from here.
        if (touch.Id != _holdTouchId ||
            (_holdSamples.Count > 0 && touch.PositionMm.DistanceTo(Mean(_holdSamples)) > HoldToleranceMm))
        {
            ResetHold();
            _holdTouchId = touch.Id;
        }

        _holdSamples.Add(touch.PositionMm);
        Step = CalibrationStep.Holding;

        if (_holdSamples.Count >= HoldRotations)
        {
            _points.Add(new CalibrationPoint(TargetsUv[_points.Count], Mean(_holdSamples)));
            ResetHold();
            Step = CalibrationStep.WaitingForRelease;
        }
    }

    private void ResetHold()
    {
        _holdSamples.Clear();
        _holdTouchId = 0;
        if (Step == CalibrationStep.Holding)
            Step = CalibrationStep.WaitingForTouch;
    }

    private static Vector2 Mean(List<Vector2> points)
    {
        Vector2 sum = Vector2.Zero;
        foreach (Vector2 p in points)
            sum += p;
        return sum / points.Count;
    }
}
