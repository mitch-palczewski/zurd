using System;
using System.Collections.Generic;
using Godot;

namespace Zurd.Lidar;

public enum CalibrationStep
{
    /// <summary>Waiting for a new touch on the current target.</summary>
    WaitingForTouch,

    /// <summary>One new, steady touch; counting rotations until it has been held long enough.</summary>
    Holding,

    /// <summary>
    /// The touch just captured or refused is still down. Only a message: a new touch on the next
    /// target counts straight away.
    /// </summary>
    WaitingForRelease,

    /// <summary>All targets captured; <see cref="CalibrationWizard.Points"/> is ready to solve.</summary>
    Finished,
}

/// <summary>What happened last, so the wall can say so until the next hold starts.</summary>
public enum CalibrationNotice
{
    None,

    /// <summary>The last touch was captured.</summary>
    Captured,

    /// <summary>The last touch was refused; <see cref="CalibrationWizard.Rejection"/> says why.</summary>
    Rejected,

    /// <summary><see cref="CalibrationWizard.StepBack"/> dropped the last capture.</summary>
    SteppedBack,
}

/// <summary>
/// Walks through the calibration targets: corners TL, TR, BR, BL (inset from the image edges), then
/// the centre. For each, it waits for one new touch, held steady for <see cref="HoldRotations"/>
/// rotations, and averages it. Each capture is checked against the earlier ones straight away
/// (<see cref="CalibrationSolver.CheckNewTouch"/>), so a touch in the wrong place is refused while
/// the person is still at the wall.
/// <para>
/// Plain C#, main thread only: pass it every <see cref="TouchFrame"/> while it runs. Only touches
/// that begin after the current target comes up count (see <see cref="TouchHold"/>), so a hand left
/// on the wall, or something in the scan plane that the baseline missed, can't block it or be
/// captured. Corners are inset because a hand next to a baseline surface (the wall's frame, a side
/// wall) isn't detected.
/// </para>
/// </summary>
public sealed class CalibrationWizard
{
    public static readonly string[] TargetNames = { "top-left", "top-right", "bottom-right", "bottom-left", "centre" };

    private readonly TouchHold _hold = new();
    private readonly List<CalibrationPoint> _points = new();

    /// <summary>The touch just captured or refused, while it is still down; 0 once it lifts.</summary>
    private int _lastTouchId;

    /// <param name="targetInset">How far the corner targets sit in from the image edges, as a fraction of the image.</param>
    public CalibrationWizard(float targetInset = 0.1f)
    {
        float lo = targetInset;
        float hi = 1f - targetInset;
        TargetsUv = new[] { new Vector2(lo, lo), new Vector2(hi, lo), new Vector2(hi, hi), new Vector2(lo, hi), new Vector2(0.5f, 0.5f) };
    }

    /// <summary>Rotations a touch must be held steady. 6 is about a second on an A1.</summary>
    public int HoldRotations
    {
        get => _hold.Rotations;
        init => _hold.Rotations = value;
    }

    /// <summary>How far a held touch may wander from its average and still count as steady; far touches get more (<see cref="TouchHold.ToleranceFraction"/>).</summary>
    public float HoldToleranceMm
    {
        get => _hold.ToleranceMm;
        init => _hold.ToleranceMm = value;
    }

    public IReadOnlyList<Vector2> TargetsUv { get; }

    public CalibrationStep Step { get; private set; } = CalibrationStep.WaitingForTouch;

    public CalibrationNotice Notice { get; private set; }

    /// <summary>Why the last touch was refused, written for the person at the wall; set while <see cref="Notice"/> is Rejected.</summary>
    public string? Rejection { get; private set; }

    /// <summary>Index into <see cref="TargetsUv"/> of the target being captured; equals the target count once finished.</summary>
    public int CurrentTarget => _points.Count;

    /// <summary>0..1 while holding.</summary>
    public float HoldProgress => _hold.Progress;

    /// <summary>The last rotation had more than one new touch, so nothing could be held.</summary>
    public bool TooManyTouches => _hold.NewTouches > 1;

    /// <summary>
    /// Touches in the last rotation that were ignored because they were already down when the
    /// target came up, not counting the one just captured. If nobody is touching, something in
    /// the scan plane isn't in the baseline.
    /// </summary>
    public int IgnoredTouches { get; private set; }

    public bool CanStepBack => _points.Count > 0 && Step != CalibrationStep.Finished;

    /// <summary>Captured so far, in target order. Complete once <see cref="Step"/> is Finished.</summary>
    public IReadOnlyList<CalibrationPoint> Points => _points;

    public void Update(TouchFrame frame)
    {
        if (Step == CalibrationStep.Finished)
            return;

        bool lastTouchDown = false;
        foreach (TrackedTouch t in frame.Touches)
        {
            if (_lastTouchId != 0 && t.Id == _lastTouchId)
                lastTouchDown = true;
        }

        if (!lastTouchDown)
            _lastTouchId = 0;

        bool held = _hold.Update(frame, out int touchId, out Vector2 positionMm);
        IgnoredTouches = Math.Max(0, _hold.IgnoredTouches - (lastTouchDown ? 1 : 0));

        if (held)
        {
            Capture(touchId, positionMm);
            return;
        }

        if (_hold.IsHolding)
        {
            // A new hold replaces whatever the wall was saying about the last touch.
            Notice = CalibrationNotice.None;
            Rejection = null;
            Step = CalibrationStep.Holding;
        }
        else
        {
            Step = _lastTouchId != 0 ? CalibrationStep.WaitingForRelease : CalibrationStep.WaitingForTouch;
        }
    }

    /// <summary>
    /// Drops the last captured target so it can be touched again. Touches that are down now don't
    /// count; they must lift and touch again.
    /// </summary>
    public bool StepBack()
    {
        if (!CanStepBack)
            return false;

        _points.RemoveAt(_points.Count - 1);
        _hold.Restart();
        _lastTouchId = 0;
        Notice = CalibrationNotice.SteppedBack;
        Rejection = null;
        Step = CalibrationStep.WaitingForTouch;
        return true;
    }

    private void Capture(int touchId, Vector2 positionMm)
    {
        var earlier = new Vector2[_points.Count];
        for (int i = 0; i < earlier.Length; i++)
            earlier[i] = _points[i].MeasuredMm;

        Rejection = CalibrationSolver.CheckNewTouch(earlier, positionMm);
        if (Rejection is null)
        {
            _points.Add(new CalibrationPoint(TargetsUv[_points.Count], positionMm));
            Notice = CalibrationNotice.Captured;
        }
        else
        {
            Notice = CalibrationNotice.Rejected;
        }

        _lastTouchId = touchId;
        Step = _points.Count == TargetsUv.Count ? CalibrationStep.Finished : CalibrationStep.WaitingForRelease;
    }
}
