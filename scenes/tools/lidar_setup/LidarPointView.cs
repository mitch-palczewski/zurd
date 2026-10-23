using System;
using System.Collections.Generic;
using Godot;

namespace Zurd.Lidar;

/// <summary>
/// Face-on 2D view of the latest <see cref="LidarScan"/>: range rings, the sensor at the centre,
/// and every point coloured by distance. Given a <see cref="Baseline"/> and a <see cref="Detection"/>
/// it also draws the baseline outline, highlights points that came closer, and marks blobs and
/// touches. Mouse wheel zooms, left-drag pans, double-click recentres.
/// </summary>
public partial class LidarPointView : Control
{
    private const float MinRangeMm = 300f;
    private const float MaxRangeLimitMm = 12000f;
    private const float PointSizePx = 3f;
    private const float ForegroundPointSizePx = 4f;
    private const float ZoomStep = 0.85f;

    /// <summary>The baseline outline breaks where neighbouring bins jump by more than this plus 15%.</summary>
    private const float BaselineBreakMm = 100f;

    private static readonly Color BackgroundColor = new(0.07f, 0.08f, 0.10f);
    private static readonly Color RingColor = new(1f, 1f, 1f, 0.10f);
    private static readonly Color AxisColor = new(1f, 1f, 1f, 0.07f);
    private static readonly Color TextColor = new(1f, 1f, 1f, 0.45f);
    private static readonly Color ZeroDegColor = new(1f, 0.62f, 0.20f);
    private static readonly Color NinetyDegColor = new(0.45f, 0.75f, 1f);
    private static readonly Color BaselineColor = new(0.45f, 0.95f, 0.80f, 0.35f);
    private static readonly Color TouchColor = new(1f, 0.35f, 0.65f);
    private static readonly Color TouchFillColor = new(1f, 0.35f, 0.65f, 0.22f);
    private static readonly Color RejectedBlobColor = new(1f, 1f, 1f, 0.30f);

    private LidarScan? _scan;
    private LidarBaseline? _baseline;
    private TouchFrame? _detection;
    private float _rangeMm = 4000f;
    private float _angleOffsetDeg;
    private bool _mirror;
    private Vector2 _pan;

    /// <summary>Raised when the visible range changes (mouse wheel or the setter), so a slider can follow.</summary>
    public event Action<float>? RangeChanged;

    /// <summary>The scan to draw. Setting it redraws.</summary>
    public LidarScan? Scan
    {
        get => _scan;
        set
        {
            _scan = value;
            QueueRedraw();
        }
    }

    /// <summary>Drawn as a faint outline. Points are dimmed while one is set, so foreground stands out.</summary>
    public LidarBaseline? Baseline
    {
        get => _baseline;
        set
        {
            _baseline = value;
            QueueRedraw();
        }
    }

    /// <summary>Foreground, blobs and touches. Only drawn while its scan is the one in <see cref="Scan"/>.</summary>
    public TouchFrame? Detection
    {
        get => _detection;
        set
        {
            _detection = value;
            QueueRedraw();
        }
    }

    /// <summary>Distance from the sensor to the edge of the view, in millimetres.</summary>
    public float RangeMm
    {
        get => _rangeMm;
        set
        {
            float clamped = Mathf.Clamp(value, MinRangeMm, MaxRangeLimitMm);
            if (Mathf.IsEqualApprox(clamped, _rangeMm))
                return;

            _rangeMm = clamped;
            QueueRedraw();
            RangeChanged?.Invoke(_rangeMm);
        }
    }

    /// <summary>Rotates the picture, in degrees. Display only; see <see cref="LidarGeometry.ToLocal"/>.</summary>
    public float AngleOffsetDeg
    {
        get => _angleOffsetDeg;
        set
        {
            _angleOffsetDeg = value;
            QueueRedraw();
        }
    }

    /// <summary>Flips the sweep direction, for a sensor mounted the other way round.</summary>
    public bool Mirror
    {
        get => _mirror;
        set
        {
            _mirror = value;
            QueueRedraw();
        }
    }

    public override void _Ready()
    {
        ClipContents = true;
        CustomMinimumSize = new Vector2(320f, 320f);
    }

    public override void _GuiInput(InputEvent @event)
    {
        switch (@event)
        {
            case InputEventMouseButton { Pressed: true, ButtonIndex: MouseButton.WheelUp }:
                RangeMm *= ZoomStep;
                AcceptEvent();
                break;

            case InputEventMouseButton { Pressed: true, ButtonIndex: MouseButton.WheelDown }:
                RangeMm /= ZoomStep;
                AcceptEvent();
                break;

            case InputEventMouseButton { Pressed: true, ButtonIndex: MouseButton.Left, DoubleClick: true }:
                _pan = Vector2.Zero;
                QueueRedraw();
                AcceptEvent();
                break;

            case InputEventMouseMotion motion when (motion.ButtonMask & MouseButtonMask.Left) != 0:
                _pan += motion.Relative;
                QueueRedraw();
                AcceptEvent();
                break;
        }
    }

    public override void _Draw()
    {
        Vector2 size = Size;
        Font font = GetThemeDefaultFont();
        int fontSize = GetThemeDefaultFontSize();

        DrawRect(new Rect2(Vector2.Zero, size), BackgroundColor);

        Vector2 origin = size * 0.5f + _pan;
        float pxPerMm = Mathf.Min(size.X, size.Y) * 0.5f / _rangeMm;

        // Detection is only meaningful against the scan it was computed from.
        TouchFrame? detection = _detection is not null && _detection.Scan == _scan ? _detection : null;

        DrawGrid(origin, size, pxPerMm, font, fontSize);
        DrawBaseline(origin, pxPerMm);
        DrawPoints(origin, size, pxPerMm, detection);
        DrawDetection(origin, pxPerMm, detection, font, fontSize);

        // Sensor, with its 0° and 90° directions so the sweep direction is obvious.
        DrawCircle(origin, 4f, Colors.White);
        DrawHeadingTick(origin, 0f, "0°", ZeroDegColor, font, fontSize);
        DrawHeadingTick(origin, 90f, "90°", NinetyDegColor, font, fontSize);

        string info = _scan is null
            ? "No scan data"
            : $"Rotation {_scan.Sequence} · {_scan.Count} points";
        if (detection is not null)
            info += $" · {detection.ConfirmedCount} touching";

        DrawString(font, new Vector2(10f, fontSize + 6f), info, HorizontalAlignment.Left, -1f, fontSize, TextColor);
        DrawString(font, new Vector2(10f, fontSize * 2f + 10f), "Wheel: zoom · drag: pan · double-click: recentre",
            HorizontalAlignment.Left, -1f, fontSize - 3, TextColor);
    }

    private void DrawGrid(Vector2 origin, Vector2 size, float pxPerMm, Font font, int fontSize)
    {
        DrawLine(new Vector2(0f, origin.Y), new Vector2(size.X, origin.Y), AxisColor);
        DrawLine(new Vector2(origin.X, 0f), new Vector2(origin.X, size.Y), AxisColor);

        float step = PickRingStepMm(_rangeMm);
        float maxRadiusPx = size.Length() + Mathf.Max(Mathf.Abs(_pan.X), Mathf.Abs(_pan.Y));

        for (float r = step; r <= MaxRangeLimitMm && r * pxPerMm <= maxRadiusPx; r += step)
        {
            float radiusPx = r * pxPerMm;
            DrawArc(origin, radiusPx, 0f, Mathf.Tau, 96, RingColor, 1f);

            string label = r >= 1000f ? $"{r / 1000f:0.#} m" : $"{r:0} mm";
            float diagonal = radiusPx * 0.7071f;
            DrawString(font, origin + new Vector2(diagonal + 3f, diagonal + fontSize), label,
                HorizontalAlignment.Left, -1f, fontSize - 3, TextColor);
        }
    }

    private void DrawBaseline(Vector2 origin, float pxPerMm)
    {
        if (_baseline is null)
            return;

        // One polyline per run of bins that sees a continuous surface, so depth edges and open
        // directions show as gaps rather than lines across empty space.
        var segment = new List<Vector2>();
        float previous = float.PositiveInfinity;

        for (int bin = 0; bin < _baseline.BinCount; bin++)
        {
            float d = _baseline.DistanceMm(bin);
            bool open = float.IsPositiveInfinity(d);
            bool continues = !open && !float.IsPositiveInfinity(previous)
                && MathF.Abs(d - previous) <= BaselineBreakMm + 0.15f * MathF.Min(d, previous);

            if (!continues)
                FlushBaselineSegment(segment);

            if (!open)
            {
                Vector2 local = LidarGeometry.ToLocal(_baseline.BinCenterDeg(bin), d, _angleOffsetDeg, _mirror);
                segment.Add(origin + new Vector2(local.X, -local.Y) * pxPerMm);
            }

            previous = d;
        }

        FlushBaselineSegment(segment);
    }

    private void FlushBaselineSegment(List<Vector2> segment)
    {
        if (segment.Count >= 2)
            DrawPolyline(segment.ToArray(), BaselineColor, 1.5f, true);
        else if (segment.Count == 1)
            DrawCircle(segment[0], 1f, BaselineColor);

        segment.Clear();
    }

    private void DrawPoints(Vector2 origin, Vector2 size, float pxPerMm, TouchFrame? detection)
    {
        if (_scan is null)
            return;

        ReadOnlySpan<LidarSample> samples = _scan.Samples;
        ReadOnlySpan<bool> foreground = detection is null ? default : detection.Foreground;
        float backgroundAlpha = _baseline is null ? 1f : 0.45f;

        for (int i = 0; i < samples.Length; i++)
        {
            LidarSample s = samples[i];
            bool isForeground = i < foreground.Length && foreground[i];
            float sizePx = isForeground ? ForegroundPointSizePx : PointSizePx;

            Vector2 local = LidarGeometry.ToLocal(s.AngleDeg, s.DistanceMm, _angleOffsetDeg, _mirror);
            // Local Y points up; the canvas Y points down.
            Vector2 p = origin + new Vector2(local.X, -local.Y) * pxPerMm;

            if (p.X < -sizePx || p.Y < -sizePx || p.X > size.X + sizePx || p.Y > size.Y + sizePx)
                continue;

            Color color;
            if (isForeground)
            {
                color = TouchColor;
            }
            else
            {
                float t = Mathf.Clamp(s.DistanceMm / _rangeMm, 0f, 1f);
                color = Color.FromHsv(Mathf.Lerp(0.13f, 0.60f, t), 0.75f, 1f, backgroundAlpha);
            }

            float half = sizePx * 0.5f;
            DrawRect(new Rect2(p.X - half, p.Y - half, sizePx, sizePx), color);
        }
    }

    private void DrawDetection(Vector2 origin, float pxPerMm, TouchFrame? detection, Font font, int fontSize)
    {
        if (detection is null)
            return;

        // Blobs that failed the size limits: a faint ring, so you can see what is being ignored.
        foreach (TouchBlob blob in detection.Blobs)
        {
            if (blob.IsTouchSized)
                continue;

            DrawArc(ToScreen(blob.CentroidMm, origin, pxPerMm), BlobRadiusPx(blob.WidthMm, pxPerMm),
                0f, Mathf.Tau, 32, RejectedBlobColor, 1f);
        }

        foreach (TrackedTouch touch in detection.Touches)
        {
            Vector2 p = ToScreen(touch.PositionMm, origin, pxPerMm);
            float radius = BlobRadiusPx(touch.WidthMm, pxPerMm);
            // Coasting through a missed rotation: same marker, half strength.
            Color ring = touch.MissedRotations > 0 ? new Color(TouchColor, 0.5f) : TouchColor;

            if (!touch.Confirmed)
            {
                DrawArc(p, radius, 0f, Mathf.Tau, 32, new Color(TouchColor, 0.6f), 1f);
                continue;
            }

            DrawCircle(p, radius, TouchFillColor);
            DrawArc(p, radius, 0f, Mathf.Tau, 48, ring, 2f);
            DrawCircle(p, 2.5f, ring);

            (float angle, float distance) = LidarGeometry.ToPolar(touch.PositionMm);
            DrawString(font, p + new Vector2(radius + 4f, fontSize * 0.35f),
                $"#{touch.Id} · {distance / 1000f:0.00} m · {angle:0}°",
                HorizontalAlignment.Left, -1f, fontSize - 2, ring);
        }
    }

    private void DrawHeadingTick(Vector2 origin, float angleDeg, string label, Color color, Font font, int fontSize)
    {
        Vector2 local = LidarGeometry.ToLocal(angleDeg, 1f, _angleOffsetDeg, _mirror);
        Vector2 dir = new(local.X, -local.Y);
        Vector2 end = origin + dir * 56f;

        DrawLine(origin, end, color, 2f);
        DrawString(font, end + dir * 6f + new Vector2(-8f, fontSize * 0.35f), label,
            HorizontalAlignment.Left, -1f, fontSize - 2, color);
    }

    /// <summary>Screen position of a point in the uncorrected lidar-local frame, as the detector reports them.</summary>
    private Vector2 ToScreen(Vector2 local, Vector2 origin, float pxPerMm)
    {
        Vector2 oriented = LidarGeometry.Orient(local, _angleOffsetDeg, _mirror);
        return origin + new Vector2(oriented.X, -oriented.Y) * pxPerMm;
    }

    private static float BlobRadiusPx(float widthMm, float pxPerMm) =>
        Mathf.Max(widthMm * 0.5f * pxPerMm + 4f, 8f);

    private static float PickRingStepMm(float rangeMm)
    {
        float[] steps = { 100f, 250f, 500f, 1000f, 2000f, 5000f };
        foreach (float step in steps)
        {
            if (rangeMm / step <= 6f)
                return step;
        }

        return 5000f;
    }
}
