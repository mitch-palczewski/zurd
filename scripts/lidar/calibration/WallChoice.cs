using System.Collections.Generic;
using Godot;

namespace Zurd.Lidar;

/// <summary>A touch button on the wall: its label and where it sits on the projected image, in UV.</summary>
public readonly record struct WallButton(string Label, Rect2 AreaUv);

/// <summary>
/// Lets the person at the wall pick one of a few <see cref="WallButton"/>s by holding a new touch on
/// it, using a calibration to find where touches land on the image. Without a calibration there's
/// no telling where a touch is, so a touch anywhere picks the first button.
/// <para>
/// Plain C#, main thread only: pass it every <see cref="TouchFrame"/>. Touches already down when it
/// starts don't count (see <see cref="TouchHold"/>).
/// </para>
/// </summary>
public sealed class WallChoice
{
    private readonly WallCalibration? _calibration;
    private readonly TouchHold _hold = new();

    public WallChoice(IReadOnlyList<WallButton> buttons, WallCalibration? calibration)
    {
        Buttons = buttons;
        _calibration = calibration;
    }

    public IReadOnlyList<WallButton> Buttons { get; }

    /// <summary>Index of the button being held, or -1.</summary>
    public int HeldButton => _hold.IsHolding ? ButtonAt(_hold.PositionMm) : -1;

    /// <summary>0..1 while a button is being held.</summary>
    public float Progress => _hold.Progress;

    /// <summary>The button a hold completed on, or null until then.</summary>
    public WallButton? Chosen { get; private set; }

    public void Update(TouchFrame frame)
    {
        if (Chosen is not null)
            return;

        if (_hold.Update(frame, out _, out Vector2 positionMm, p => ButtonAt(p) >= 0))
        {
            int index = ButtonAt(positionMm);
            if (index >= 0)
                Chosen = Buttons[index];
        }
    }

    private int ButtonAt(Vector2 positionMm)
    {
        if (_calibration is null)
            return Buttons.Count > 0 ? 0 : -1;

        if (!_calibration.TryMapToUv(positionMm, out Vector2 uv))
            return -1;

        for (int i = 0; i < Buttons.Count; i++)
        {
            if (Buttons[i].AreaUv.HasPoint(uv))
                return i;
        }

        return -1;
    }
}
