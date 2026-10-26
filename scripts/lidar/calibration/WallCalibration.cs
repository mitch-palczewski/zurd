using System;
using System.Collections.Generic;
using Godot;

namespace Zurd.Lidar;

/// <summary>One calibration target: where it was shown, and where the lidar saw the touch on it.</summary>
/// <param name="TargetUv">Position on the projected image, 0..1 with (0, 0) at the top-left.</param>
/// <param name="MeasuredMm">Averaged touch position, lidar-local millimetres.</param>
public readonly record struct CalibrationPoint(Vector2 TargetUv, Vector2 MeasuredMm);

/// <summary>
/// Where one lidar's touches land on its wall's projected image. UV (0, 0) is the image's top-left
/// and V grows downward, like Godot screen coordinates, so UV × the projector's resolution is a
/// pixel. Immutable; built by <see cref="CalibrationSolver"/> or loaded by <see cref="LidarConfigStore"/>.
/// </summary>
public sealed class WallCalibration
{
    public WallCalibration(
        string serial,
        Homography lidarToUv,
        IReadOnlyList<CalibrationPoint> points,
        float centreErrorMm,
        DateTime calibratedAtUtc)
    {
        if (!lidarToUv.TryInvert(out Homography uvToLidar))
            throw new ArgumentException("The lidar-to-UV transform is not invertible.", nameof(lidarToUv));

        Serial = serial;
        LidarToUv = lidarToUv;
        UvToLidar = uvToLidar;
        Points = points;
        CentreErrorMm = centreErrorMm;
        CalibratedAtUtc = calibratedAtUtc;
    }

    /// <summary>The lidar this calibration belongs to.</summary>
    public string Serial { get; }

    public Homography LidarToUv { get; }

    public Homography UvToLidar { get; }

    /// <summary>The targets and touches it was solved from: corners TL, TR, BR, BL, then the centre.</summary>
    public IReadOnlyList<CalibrationPoint> Points { get; }

    /// <summary>
    /// How far, on the wall, the centre touch landed from where the four corners predicted. The
    /// honest accuracy figure: four points alone always fit perfectly.
    /// </summary>
    public float CentreErrorMm { get; }

    public DateTime CalibratedAtUtc { get; }

    /// <summary>Maps a lidar-local position (as touches report it) onto the projected image.</summary>
    public bool TryMapToUv(Vector2 lidarMm, out Vector2 uv) => LidarToUv.TryMap(lidarMm, out uv);

    /// <summary>
    /// The projected image, grown by <paramref name="marginUv"/> on every side, as a quad in
    /// lidar-local millimetres (corners TL, TR, BR, BL). With a margin of 0 it is the image's outline.
    /// </summary>
    public bool TryGetArea(float marginUv, out Vector2[] quadMm)
    {
        float lo = -marginUv;
        float hi = 1f + marginUv;
        Vector2[] uvCorners = { new(lo, lo), new(hi, lo), new(hi, hi), new(lo, hi) };

        quadMm = new Vector2[4];
        for (int i = 0; i < 4; i++)
        {
            if (!UvToLidar.TryMap(uvCorners[i], out quadMm[i]))
                return false;
        }

        return true;
    }
}
