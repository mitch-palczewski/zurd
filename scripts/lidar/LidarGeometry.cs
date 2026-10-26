using System.Collections.Generic;
using Godot;

namespace Zurd.Lidar;

/// <summary>Conversions between the sensor's polar readings and 2D coordinates.</summary>
public static class LidarGeometry
{
    /// <summary>
    /// Converts a polar reading into the lidar-local frame, in millimetres.
    /// <para>
    /// Frame: origin at the sensor, +Y along the sensor's 0° axis, +X toward 90° (the sensor
    /// sweeps clockwise as seen from above, so 90° is to the right of 0°). Y points up, like a
    /// math plot; flip Y when drawing on a Godot canvas.
    /// </para>
    /// <para>
    /// <paramref name="mirror"/> flips the sweep direction first, then
    /// <paramref name="angleOffsetDeg"/> rotates the result. Together they cover both ways the
    /// sensor can be mounted relative to the wall it watches.
    /// </para>
    /// </summary>
    public static Vector2 ToLocal(float angleDeg, float distanceMm, float angleOffsetDeg = 0f, bool mirror = false)
    {
        float a = mirror ? -angleDeg : angleDeg;
        float rad = Mathf.DegToRad(a + angleOffsetDeg);
        return new Vector2(Mathf.Sin(rad), Mathf.Cos(rad)) * distanceMm;
    }

    /// <summary>
    /// Applies the mounting correction to a point already in the uncorrected lidar-local frame, so
    /// <c>Orient(ToLocal(a, d), offset, mirror)</c> equals <c>ToLocal(a, d, offset, mirror)</c>. Use it
    /// for positions the detector reports, such as touch centroids.
    /// </summary>
    public static Vector2 Orient(Vector2 local, float angleOffsetDeg, bool mirror)
    {
        Vector2 p = mirror ? new Vector2(-local.X, local.Y) : local;
        // Headings grow clockwise in this frame, while Rotated() turns counter-clockwise.
        return p.Rotated(-Mathf.DegToRad(angleOffsetDeg));
    }

    /// <summary>True if <paramref name="p"/> is inside or on the edge of a convex polygon, in either winding order.</summary>
    public static bool IsInsideConvex(Vector2 p, IReadOnlyList<Vector2> polygon)
    {
        int sign = 0;
        for (int i = 0; i < polygon.Count; i++)
        {
            Vector2 a = polygon[i];
            Vector2 b = polygon[(i + 1) % polygon.Count];
            float cross = (b - a).Cross(p - a);
            if (cross == 0f)
                continue;

            int s = cross > 0f ? 1 : -1;
            if (sign == 0)
                sign = s;
            else if (s != sign)
                return false;
        }

        return true;
    }

    /// <summary>Inverse of <see cref="ToLocal"/> with no offset or mirror: heading 0..360 and distance in millimetres.</summary>
    public static (float AngleDeg, float DistanceMm) ToPolar(Vector2 local)
    {
        float angle = Mathf.PosMod(Mathf.RadToDeg(Mathf.Atan2(local.X, local.Y)), 360f);
        return (angle, local.Length());
    }
}
