using System.Collections.Generic;
using Godot;

namespace Zurd.Lidar;

/// <summary>
/// What the projector shows during calibration: the targets to touch, with a progress ring on the
/// current one; touch buttons for choosing what to do with the result; and an optional follow test
/// that puts a dot under every live touch. The background is black, which is "no light" on a
/// projector. Pure display: <see cref="CalibrationPanel"/> sets what it shows.
/// </summary>
public partial class CalibrationTargetView : Control
{
    private static readonly Color TextColor = Colors.White;
    private static readonly Color FooterColor = new(1f, 1f, 1f, 0.45f);
    private static readonly Color TargetColor = Colors.White;
    private static readonly Color PendingTargetColor = new(1f, 1f, 1f, 0.25f);
    private static readonly Color DoneColor = new(0.30f, 0.85f, 0.45f);
    private static readonly Color ButtonFillColor = new(0.30f, 0.85f, 0.45f, 0.45f);
    private static readonly Color GridColor = new(1f, 1f, 1f, 0.12f);
    private static readonly Color BorderColor = new(1f, 1f, 1f, 0.5f);
    private static readonly Color TouchColor = new(1f, 0.35f, 0.65f);

    private IReadOnlyList<Vector2>? _targets;
    private int _currentTarget;
    private float _progress;
    private IReadOnlyList<WallButton>? _buttons;
    private int _heldButton = -1;
    private string _message = "";
    private string _footer = "";
    private IReadOnlyList<(int Id, Vector2 Uv)>? _touches;

    public override void _Ready()
    {
        // Offsets too: anchors alone keep the zero size this view had when it entered the window.
        SetAnchorsAndOffsetsPreset(LayoutPreset.FullRect);
    }

    /// <summary>Shows the targets: earlier ones ticked off, <paramref name="current"/> highlighted with a progress ring.</summary>
    public void ShowTargets(IReadOnlyList<Vector2> targetsUv, int current, float progress, string message)
    {
        _targets = targetsUv;
        _buttons = null;
        _currentTarget = current;
        _progress = progress;
        _message = message;
        QueueRedraw();
    }

    /// <summary>Shows a message above touch buttons; <paramref name="held"/> (or -1) fills from the left as <paramref name="progress"/> grows.</summary>
    public void ShowChoice(string message, IReadOnlyList<WallButton> buttons, int held, float progress)
    {
        _targets = null;
        _buttons = buttons;
        _heldButton = held;
        _progress = progress;
        _message = message;
        QueueRedraw();
    }

    /// <summary>Hides targets and buttons and shows only a message; an empty message leaves the screen black.</summary>
    public void ShowMessage(string message)
    {
        _targets = null;
        _buttons = null;
        _message = message;
        QueueRedraw();
    }

    /// <summary>A small line along the bottom edge, such as which keys do what; empty hides it.</summary>
    public void SetFooter(string text)
    {
        if (text == _footer)
            return;

        _footer = text;
        QueueRedraw();
    }

    /// <summary>Follow test: a dot at each touch's UV, over a 10% grid. Null turns it off.</summary>
    public void ShowTouches(IReadOnlyList<(int Id, Vector2 Uv)>? touches)
    {
        _touches = touches;
        QueueRedraw();
    }

    public override void _Draw()
    {
        Vector2 size = Size;
        float unit = Mathf.Min(size.X, size.Y);
        Font font = ThemeDB.FallbackFont;

        DrawRect(new Rect2(Vector2.Zero, size), Colors.Black);

        if (_touches is not null)
            DrawGrid(size);

        if (_targets is not null)
            DrawTargets(size, unit);

        if (_buttons is not null)
            DrawButtons(size, unit, font);

        if (_touches is not null)
            DrawTouches(size, unit, font);

        if (_message.Length > 0)
        {
            // Between the top targets (10% down) and the centre one, or well above the buttons.
            int fontSize = Mathf.Max(16, (int)(unit / 22f));
            float top = _buttons is null ? 0.3f : 0.2f;
            DrawMultilineString(font, new Vector2(size.X * 0.1f, size.Y * top), _message, HorizontalAlignment.Center,
                size.X * 0.8f, fontSize, -1, TextColor);
        }

        if (_footer.Length > 0)
        {
            int fontSize = Mathf.Max(12, (int)(unit / 45f));
            DrawString(font, new Vector2(0f, size.Y - fontSize), _footer, HorizontalAlignment.Center, size.X, fontSize,
                FooterColor);
        }
    }

    private void DrawButtons(Vector2 size, float unit, Font font)
    {
        int fontSize = Mathf.Max(18, (int)(unit / 14f));

        for (int i = 0; i < _buttons!.Count; i++)
        {
            var rect = new Rect2(_buttons[i].AreaUv.Position * size, _buttons[i].AreaUv.Size * size);

            if (i == _heldButton && _progress > 0f)
                DrawRect(new Rect2(rect.Position, new Vector2(rect.Size.X * Mathf.Min(_progress, 1f), rect.Size.Y)), ButtonFillColor);

            DrawRect(rect, TargetColor, false, 3f);

            float baseline = rect.GetCenter().Y + (font.GetAscent(fontSize) - font.GetDescent(fontSize)) * 0.5f;
            DrawString(font, new Vector2(rect.Position.X, baseline), _buttons[i].Label, HorizontalAlignment.Center,
                rect.Size.X, fontSize, TextColor);
        }
    }

    private void DrawTargets(Vector2 size, float unit)
    {
        float radius = unit * 0.035f;

        for (int i = 0; i < _targets!.Count; i++)
        {
            Vector2 p = _targets[i] * size;

            if (i < _currentTarget)
            {
                DrawCircle(p, radius * 0.5f, DoneColor);
            }
            else if (i == _currentTarget)
            {
                float arm = radius * 1.8f;
                DrawLine(p - new Vector2(arm, 0f), p + new Vector2(arm, 0f), TargetColor, 2f);
                DrawLine(p - new Vector2(0f, arm), p + new Vector2(0f, arm), TargetColor, 2f);
                DrawArc(p, radius, 0f, Mathf.Tau, 64, TargetColor, 3f);

                if (_progress > 0f)
                {
                    float start = -Mathf.Pi / 2f;
                    DrawArc(p, radius * 1.4f, start, start + Mathf.Tau * Mathf.Min(_progress, 1f), 64, DoneColor,
                        radius * 0.25f);
                }
            }
            else
            {
                DrawArc(p, radius * 0.5f, 0f, Mathf.Tau, 32, PendingTargetColor, 2f);
            }
        }
    }

    private void DrawGrid(Vector2 size)
    {
        for (int i = 1; i < 10; i++)
        {
            float x = size.X * i / 10f;
            float y = size.Y * i / 10f;
            DrawLine(new Vector2(x, 0f), new Vector2(x, size.Y), GridColor);
            DrawLine(new Vector2(0f, y), new Vector2(size.X, y), GridColor);
        }

        DrawRect(new Rect2(Vector2.One, size - new Vector2(2f, 2f)), BorderColor, false, 2f);
    }

    private void DrawTouches(Vector2 size, float unit, Font font)
    {
        float radius = unit * 0.02f;
        int fontSize = Mathf.Max(14, (int)(unit / 40f));

        foreach ((int id, Vector2 uv) in _touches!)
        {
            Vector2 p = uv * size;
            DrawCircle(p, radius, TouchColor);
            DrawString(font, p + new Vector2(radius * 1.4f, fontSize * 0.35f), $"#{id}", HorizontalAlignment.Left, -1f,
                fontSize, TouchColor);
        }
    }
}
