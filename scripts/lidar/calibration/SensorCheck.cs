using System;
using System.Collections.Generic;
using Godot;

namespace Zurd.Lidar;

public enum SensorVerdict
{
    /// <summary>Too few directions saw a surface in both baselines to compare them.</summary>
    CannotTell,

    Unchanged,

    /// <summary>The sensor has probably been shifted or turned, so its calibration may be off.</summary>
    Moved,
}

/// <summary>
/// Compares a new baseline with the one saved alongside the calibration, to notice a sensor that
/// was bumped or remounted since it was calibrated. It estimates how far the sensor has shifted
/// and turned from how the distance in every direction changed, fitting all directions at once and
/// leaving out the ones that disagree, such as furniture moved around the room.
/// <para>
/// The thresholds are first guesses, to be tuned against a real wall. The message shows the
/// estimates, so a false alarm is easy to spot.
/// </para>
/// </summary>
/// <param name="ShiftMm">Estimated shift of the sensor, in millimetres; every touch moves by about as much. NaN if the surroundings couldn't pin it down.</param>
/// <param name="TurnedDeg">Estimated turn of the sensor, in degrees; NaN with <paramref name="ShiftMm"/>.</param>
/// <param name="ChangedShare">Share of the compared directions whose distance changed, 0..1.</param>
/// <param name="ComparedBins">Directions where both baselines saw a surface.</param>
public sealed record SensorCheck(SensorVerdict Verdict, float ShiftMm, float TurnedDeg, float ChangedShare, int ComparedBins)
{
    /// <summary>A shift this big or bigger counts as moved.</summary>
    public const float MaxShiftMm = 15f;

    /// <summary>A turn this big or bigger counts as moved. At 2 m, 1° moves a touch about 35 mm.</summary>
    public const float MaxTurnDeg = 1f;

    /// <summary>A direction counts as changed when its distance differs by more than this...</summary>
    public const float MinChangeMm = 15f;

    /// <summary>...or by more than this fraction of the distance, whichever is larger.</summary>
    public const float RelativeChange = 0.01f;

    /// <summary>
    /// More than this share of directions changing counts as moved, whatever the estimates say: a
    /// big move is beyond what the fit can follow.
    /// </summary>
    public const float MaxChangedShare = 0.4f;

    /// <summary>Fewer compared directions than this can't tell; 40 bins of 0.5° is 20° of view.</summary>
    public const int MinComparedBins = 40;

    /// <summary>Neighbouring bins further apart than this, plus 15%, are a depth edge, where a surface's slope is unknown.</summary>
    private const float EdgeJumpMm = 100f;

    /// <summary>Surfaces seen more side-on than about 76° (slope over distance above 4) say little and are left out of the fit.</summary>
    private const float MaxSlope = 4f;

    /// <summary>
    /// After each fit, directions that miss it by more than the next of these are left out of the
    /// following one. Tightening in steps keeps a big change, such as a chair moved close to the
    /// sensor, from dragging the first fit so far that the good directions get left out instead.
    /// </summary>
    private static readonly float[] OutlierStepsMm = { 200f, 50f, 20f, 10f };

    public static SensorCheck Compare(LidarBaseline reference, LidarBaseline current)
    {
        if (reference.BinCount != current.BinCount)
            return new SensorCheck(SensorVerdict.CannotTell, float.NaN, float.NaN, 0f, 0);

        int bins = reference.BinCount;
        float binRad = Mathf.DegToRad(reference.BinDeg);
        var rows = new List<Row>();
        int compared = 0;
        int changed = 0;

        for (int b = 0; b < bins; b++)
        {
            float before = reference.DistanceMm(b);
            float now = current.DistanceMm(b);
            if (float.IsPositiveInfinity(before) || float.IsPositiveInfinity(now))
                continue;

            compared++;
            float change = now - before;
            if (MathF.Abs(change) > MathF.Max(MinChangeMm, before * RelativeChange))
                changed++;

            float previous = reference.DistanceMm((b - 1 + bins) % bins);
            float next = reference.DistanceMm((b + 1) % bins);
            if (IsEdge(before, previous) || IsEdge(before, next))
                continue;

            // How this direction's distance changes for a small shift (x, y) and turn of the sensor,
            // from the surface's position and slope: a shift along the beam changes the distance
            // directly, one across it slides the beam along the surface, and a turn does the same.
            float slope = (next - previous) / (2f * binRad);
            if (MathF.Abs(slope) > MaxSlope * before)
                continue;

            float angle = Mathf.DegToRad(reference.BinCenterDeg(b));
            var along = new Vector2(MathF.Sin(angle), MathF.Cos(angle));
            var across = new Vector2(MathF.Cos(angle), -MathF.Sin(angle));
            float slide = slope / before;
            rows.Add(new Row(-along.X + slide * across.X, -along.Y + slide * across.Y, slope, change));
        }

        if (compared < MinComparedBins)
            return new SensorCheck(SensorVerdict.CannotTell, float.NaN, float.NaN, 0f, compared);

        float share = changed / (float)compared;
        if (!TryFitMotion(rows, out Vector2 shift, out float turnRad))
        {
            SensorVerdict verdict = share > MaxChangedShare ? SensorVerdict.Moved : SensorVerdict.CannotTell;
            return new SensorCheck(verdict, float.NaN, float.NaN, share, compared);
        }

        float shiftMm = shift.Length();
        float turnedDeg = MathF.Abs(Mathf.RadToDeg(turnRad));
        bool moved = share > MaxChangedShare || shiftMm >= MaxShiftMm || turnedDeg >= MaxTurnDeg;
        return new SensorCheck(moved ? SensorVerdict.Moved : SensorVerdict.Unchanged, shiftMm, turnedDeg, share, compared);
    }

    private static bool IsEdge(float distance, float neighbour) =>
        float.IsPositiveInfinity(neighbour) || MathF.Abs(neighbour - distance) > EdgeJumpMm + 0.15f * MathF.Min(distance, neighbour);

    /// <summary>One direction: its change in distance ≈ X·shift.x + Y·shift.y + Turn·turn (radians).</summary>
    private readonly record struct Row(float X, float Y, float Turn, float Change);

    /// <summary>
    /// Least-squares fit of shift and turn to the rows, repeated while leaving out the rows that
    /// miss it (<see cref="OutlierStepsMm"/>), so the directions that changed for some other reason
    /// don't pull it.
    /// </summary>
    private static bool TryFitMotion(List<Row> rows, out Vector2 shift, out float turnRad)
    {
        // The turn is solved as an arc length at 1 m, so all three unknowns are millimetres and the
        // equations stay well balanced.
        const double armMm = 1000.0;

        var x = new double[3];
        var used = new bool[rows.Count];
        Array.Fill(used, true);

        for (int pass = 0; pass <= OutlierStepsMm.Length; pass++)
        {
            var m = new double[3, 3];
            var v = new double[3];
            int count = 0;
            for (int i = 0; i < rows.Count; i++)
            {
                if (!used[i])
                    continue;

                double[] j = { rows[i].X, rows[i].Y, rows[i].Turn / armMm };
                for (int r = 0; r < 3; r++)
                {
                    v[r] += j[r] * rows[i].Change;
                    for (int c = 0; c < 3; c++)
                        m[r, c] += j[r] * j[c];
                }

                count++;
            }

            if (count < MinComparedBins || !TrySolve(m, v, out x))
            {
                shift = Vector2.Zero;
                turnRad = 0f;
                return false;
            }

            if (pass == OutlierStepsMm.Length)
                break;

            for (int i = 0; i < rows.Count; i++)
            {
                double predicted = rows[i].X * x[0] + rows[i].Y * x[1] + rows[i].Turn / armMm * x[2];
                used[i] = Math.Abs(predicted - rows[i].Change) <= OutlierStepsMm[pass];
            }
        }

        shift = new Vector2((float)x[0], (float)x[1]);
        turnRad = (float)(x[2] / armMm);
        return true;
    }

    /// <summary>Solves the 3×3 system m·x = v by elimination; false if it is nearly singular (a direction the surroundings can't pin down).</summary>
    private static bool TrySolve(double[,] m, double[] v, out double[] x)
    {
        var a = new double[3, 4];
        for (int r = 0; r < 3; r++)
        {
            for (int c = 0; c < 3; c++)
                a[r, c] = m[r, c];
            a[r, 3] = v[r];
        }

        double scale = Math.Max(Math.Max(m[0, 0], m[1, 1]), m[2, 2]);
        x = new double[3];
        for (int col = 0; col < 3; col++)
        {
            int pivot = col;
            for (int r = col + 1; r < 3; r++)
            {
                if (Math.Abs(a[r, col]) > Math.Abs(a[pivot, col]))
                    pivot = r;
            }

            if (Math.Abs(a[pivot, col]) <= 1e-6 * scale)
                return false;

            for (int c = 0; c < 4; c++)
                (a[col, c], a[pivot, c]) = (a[pivot, c], a[col, c]);

            for (int r = 0; r < 3; r++)
            {
                if (r == col)
                    continue;

                double f = a[r, col] / a[col, col];
                for (int c = col; c < 4; c++)
                    a[r, c] -= f * a[col, c];
            }
        }

        for (int r = 0; r < 3; r++)
            x[r] = a[r, 3] / a[r, r];
        return true;
    }
}
