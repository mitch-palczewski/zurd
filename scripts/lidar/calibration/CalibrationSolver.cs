using System;
using System.Collections.Generic;
using Godot;

namespace Zurd.Lidar;

public enum CalibrationQuality
{
    Good,
    Fair,
    Poor,
}

/// <summary>What <see cref="CalibrationSolver.Solve"/> concluded.</summary>
/// <param name="Calibration">The result, or null if the touches can't make a sensible calibration.</param>
/// <param name="Error">Why it failed, written for the person at the wall; null on success.</param>
/// <param name="ResidualsMm">For each point, how far its touch is from where the final fit puts its target.</param>
public sealed record CalibrationSolveResult(
    WallCalibration? Calibration,
    string? Error,
    CalibrationQuality Quality,
    float CentreErrorMm,
    IReadOnlyList<float> ResidualsMm);

/// <summary>
/// Turns five calibration touches (corners TL, TR, BR, BL, then the centre) into a
/// <see cref="WallCalibration"/>. The corners alone fix the transform exactly, so the centre is
/// held back as a check, then all five are fitted together for the result.
/// </summary>
public static class CalibrationSolver
{
    /// <summary>Centre check at or under this is good. A fingertip is about 15 mm across.</summary>
    public const float GoodCentreErrorMm = 25f;

    /// <summary>Centre check over this is poor: redo the calibration.</summary>
    public const float FairCentreErrorMm = 60f;

    /// <summary>Calibration touches closer together than this mean the same spot was touched twice.</summary>
    public const float MinTouchSpacingMm = 100f;

    /// <summary>
    /// Each corner of the touched shape must measure between this and 180° minus this. A projected
    /// image's corners are near 90°, even with keystone, so a corner outside that range means a
    /// touch landed in the wrong place.
    /// </summary>
    public const float MinCornerTurnDeg = 20f;

    /// <summary>
    /// Checks a new calibration touch against the ones already captured (in target order: corners
    /// TL, TR, BR, BL, then the centre), so a touch in the wrong place can be refused while the
    /// person is still at the wall. Returns why it can't be used, written for them, or null.
    /// </summary>
    public static string? CheckNewTouch(IReadOnlyList<Vector2> earlierMm, Vector2 touchMm)
    {
        for (int i = 0; i < earlierMm.Count; i++)
        {
            float spacing = touchMm.DistanceTo(earlierMm[i]);
            if (spacing < MinTouchSpacingMm)
                return $"That was only {spacing / 10f:0} cm from the {CalibrationWizard.TargetNames[i]} touch.";
        }

        switch (earlierMm.Count)
        {
            case 2 when Turn(earlierMm[0], earlierMm[1], touchMm) == 0:
                return "That lines up with the first two corners.";

            case 3 when !IsConvexQuad(new[] { earlierMm[0], earlierMm[1], earlierMm[2], touchMm }):
                return "That doesn't make a clean four-sided shape with the other three corners.";

            case 4 when !LidarGeometry.IsInsideConvex(touchMm, earlierMm):
                return "That landed outside the four corners.";

            default:
                return null;
        }
    }

    public static CalibrationSolveResult Solve(string serial, IReadOnlyList<CalibrationPoint> points)
    {
        if (points.Count != 5)
            return Fail($"Expected 5 calibration points, got {points.Count}.");

        var cornersMm = new Vector2[4];
        var cornersUv = new Vector2[4];
        for (int i = 0; i < 4; i++)
        {
            cornersMm[i] = points[i].MeasuredMm;
            cornersUv[i] = points[i].TargetUv;
        }

        CalibrationPoint centre = points[4];

        for (int i = 0; i < 4; i++)
        {
            float spacing = cornersMm[i].DistanceTo(cornersMm[(i + 1) % 4]);
            if (spacing < MinTouchSpacingMm)
                return Fail($"Two neighbouring corner touches are only {spacing:0} mm apart. Was the same spot touched twice?");
        }

        if (!IsConvexQuad(cornersMm))
        {
            return Fail("The corner touches don't form a clean four-sided shape. Touch the corners in " +
                "the order shown (top-left, top-right, bottom-right, bottom-left).");
        }

        if (!LidarGeometry.IsInsideConvex(centre.MeasuredMm, cornersMm))
            return Fail("The centre touch landed outside the four corners.");

        // Check: fit the corners only, then see how far the centre target lands from the centre touch.
        if (!Homography.TryFit(cornersMm, cornersUv, out Homography fromCorners) ||
            !fromCorners.TryInvert(out Homography cornersUvToMm) ||
            !cornersUvToMm.TryMap(centre.TargetUv, out Vector2 predictedCentreMm))
        {
            return Fail("Could not solve the corner touches. Try again.");
        }

        float centreErrorMm = predictedCentreMm.DistanceTo(centre.MeasuredMm);

        // Result: all five points together.
        var allMm = new Vector2[5];
        var allUv = new Vector2[5];
        for (int i = 0; i < 5; i++)
        {
            allMm[i] = points[i].MeasuredMm;
            allUv[i] = points[i].TargetUv;
        }

        if (!Homography.TryFit(allMm, allUv, out Homography lidarToUv) ||
            !lidarToUv.TryInvert(out Homography uvToMm))
        {
            return Fail("Could not solve the calibration touches. Try again.");
        }

        var residuals = new float[5];
        for (int i = 0; i < 5; i++)
        {
            residuals[i] = uvToMm.TryMap(allUv[i], out Vector2 fitted)
                ? fitted.DistanceTo(allMm[i])
                : float.PositiveInfinity;
        }

        CalibrationQuality quality = centreErrorMm <= GoodCentreErrorMm ? CalibrationQuality.Good
            : centreErrorMm <= FairCentreErrorMm ? CalibrationQuality.Fair
            : CalibrationQuality.Poor;

        var calibration = new WallCalibration(serial, lidarToUv, points, centreErrorMm, DateTime.UtcNow);
        return new CalibrationSolveResult(calibration, null, quality, centreErrorMm, residuals);
    }

    private static CalibrationSolveResult Fail(string error) =>
        new(null, error, CalibrationQuality.Poor, float.PositiveInfinity, Array.Empty<float>());

    /// <summary>True if the corners, in order, turn the same way at every corner (either winding), each by a clear amount.</summary>
    private static bool IsConvexQuad(Vector2[] q)
    {
        int sign = 0;
        for (int i = 0; i < 4; i++)
        {
            int s = Turn(q[i], q[(i + 1) % 4], q[(i + 2) % 4]);
            if (s == 0 || (sign != 0 && s != sign))
                return false;
            sign = s;
        }

        return true;
    }

    /// <summary>
    /// Which way the path a → b → c turns at b: 1 or -1, or 0 if it goes nearly straight on or
    /// nearly doubles back (within <see cref="MinCornerTurnDeg"/>).
    /// </summary>
    private static int Turn(Vector2 a, Vector2 b, Vector2 c)
    {
        Vector2 inbound = b - a;
        Vector2 outbound = c - b;
        float lengths = inbound.Length() * outbound.Length();
        if (lengths <= 0f)
            return 0;

        float sin = inbound.Cross(outbound) / lengths;
        if (MathF.Abs(sin) < MathF.Sin(Mathf.DegToRad(MinCornerTurnDeg)))
            return 0;

        return sin > 0f ? 1 : -1;
    }
}
