using System;
using System.Collections.Generic;
using Godot;

namespace Zurd.Lidar;

/// <summary>
/// The calibration section of the setup scene. Picks the projector screen, opens the target window,
/// runs <see cref="CalibrationWizard"/>, solves with <see cref="CalibrationSolver"/>, and offers the
/// result. Saving and applying a calibration is <see cref="LidarSetup"/>'s job, via
/// <see cref="CalibrationAccepted"/>.
/// </summary>
public partial class CalibrationPanel : VBoxContainer
{
    /// <summary>Screen id for a plain test window on the setup window's own screen.</summary>
    private const int TestWindowScreen = -1;

    private static readonly Color DimTextColor = new(0.72f, 0.74f, 0.80f);
    private static readonly Color GoodColor = new(0.30f, 0.78f, 0.40f);
    private static readonly Color FairColor = new(0.95f, 0.70f, 0.20f);
    private static readonly Color PoorColor = new(0.90f, 0.30f, 0.30f);

    private Label _status = null!;
    private Label _windowInfo = null!;
    private OptionButton _screenPicker = null!;
    private Button _windowButton = null!;
    private Button _startButton = null!;
    private CheckBox _followCheck = null!;
    private VBoxContainer _resultBox = null!;
    private Label _resultLabel = null!;
    private Button _saveButton = null!;

    private Window? _targetWindow;
    private CalibrationTargetView? _targetView;
    private bool? _embedSubwindowsBefore;

    private CalibrationWizard? _wizard;
    private CalibrationSolveResult? _result;
    private WallCalibration? _calibration;

    private bool _streaming;
    private bool _hasBaseline;
    private string? _serial;

    /// <summary>A solved calibration the user chose to keep.</summary>
    public event Action<WallCalibration>? CalibrationAccepted;

    /// <summary>Raised when capturing starts or stops. While it runs, detection should ignore any old calibrated area.</summary>
    public event Action<bool>? CalibratingChanged;

    public bool IsCalibrating => _wizard is not null;

    /// <summary>Screen index the targets go on, or -1 for a test window on this screen.</summary>
    public int SelectedScreen => _screenPicker.ItemCount == 0 ? TestWindowScreen : _screenPicker.GetItemId(_screenPicker.Selected);

    public override void _Ready()
    {
        AddThemeConstantOverride("separation", 8);
        BuildUi();
        RefreshScreens();
        Refresh();
    }

    public override void _ExitTree()
    {
        // The target window is our child and leaves with us; put the root's setting back.
        RestoreEmbedding();
    }

    public override void _Process(double delta)
    {
        // The window settles into its final size a frame or so after opening, so keep this current.
        _windowInfo.Visible = _targetWindow is not null;
        if (_targetWindow is null)
            return;

        int screen = _targetWindow.CurrentScreen;
        Vector2I windowSize = _targetWindow.Size;
        Vector2I screenSize = DisplayServer.ScreenGetSize(screen);
        string text = windowSize == screenSize
            ? $"Target window: {windowSize.X}×{windowSize.Y} on screen {screen + 1}."
            : $"Target window: {windowSize.X}×{windowSize.Y} on screen {screen + 1}, which is {screenSize.X}×{screenSize.Y}.";

        if (_windowInfo.Text != text)
            _windowInfo.Text = text;
    }

    // ------------------------------------------------------------------ called by the setup scene

    /// <summary>Call whenever the connection, baseline or lidar changes.</summary>
    public void SetContext(bool streaming, bool hasBaseline, string? serial)
    {
        _streaming = streaming;
        _hasBaseline = hasBaseline;
        _serial = serial;

        if (!streaming && _wizard is not null)
            StopWizard();

        Refresh();
    }

    /// <summary>The calibration in use, for the follow test and the status line.</summary>
    public void SetCalibration(WallCalibration? calibration)
    {
        _calibration = calibration;
        if (calibration is null)
            _followCheck.ButtonPressed = false;
        Refresh();
    }

    /// <summary>Selects the screen used last time for this lidar, if it still exists.</summary>
    public void PreferScreen(int? screen)
    {
        if (screen is null || _targetWindow is not null)
            return;

        int index = _screenPicker.GetItemIndex(screen.Value);
        if (index >= 0)
            _screenPicker.Select(index);
    }

    /// <summary>Feed every new rotation.</summary>
    public void Process(TouchFrame frame)
    {
        if (_wizard is not null)
        {
            _wizard.Update(frame);
            if (_wizard.Step == CalibrationStep.Finished)
                FinishWizard();
            else
                ShowWizardProgress();
        }
        else if (_followCheck.ButtonPressed)
        {
            ShowFollowTest(frame);
        }
    }

    // ------------------------------------------------------------------ UI

    private void BuildUi()
    {
        _status = new Label { AutowrapMode = TextServer.AutowrapMode.WordSmart, CustomMinimumSize = new Vector2(240f, 0f) };
        _status.AddThemeColorOverride("font_color", DimTextColor);
        AddChild(_status);

        var screenRow = new HBoxContainer();
        screenRow.AddThemeConstantOverride("separation", 6);
        AddChild(screenRow);

        _screenPicker = new OptionButton
        {
            SizeFlagsHorizontal = SizeFlags.ExpandFill,
            TooltipText = "The projector showing this wall. The test window is for trying the wizard at a desk.",
        };
        screenRow.AddChild(_screenPicker);

        var refreshScreens = new Button { Text = "Refresh", TooltipText = "Re-scan for screens, e.g. after plugging in a projector." };
        refreshScreens.Pressed += RefreshScreens;
        screenRow.AddChild(refreshScreens);

        _windowInfo = new Label
        {
            AutowrapMode = TextServer.AutowrapMode.WordSmart,
            CustomMinimumSize = new Vector2(240f, 0f),
            Visible = false,
        };
        _windowInfo.AddThemeColorOverride("font_color", DimTextColor);
        AddChild(_windowInfo);

        var buttonRow = new HBoxContainer();
        buttonRow.AddThemeConstantOverride("separation", 6);
        AddChild(buttonRow);

        _windowButton = new Button { SizeFlagsHorizontal = SizeFlags.ExpandFill };
        _windowButton.Pressed += () =>
        {
            if (_targetWindow is null)
                OpenTargetWindow();
            else
                CloseTargetWindow();
        };
        buttonRow.AddChild(_windowButton);

        _startButton = new Button { SizeFlagsHorizontal = SizeFlags.ExpandFill };
        _startButton.Pressed += () =>
        {
            if (_wizard is null)
                StartWizard();
            else
                StopWizard();
        };
        buttonRow.AddChild(_startButton);

        _followCheck = new CheckBox
        {
            Text = "Follow test: show touches on the wall",
            TooltipText = "Draws a dot on the projector under every touch. It should land under your finger.",
        };
        _followCheck.Toggled += on =>
        {
            if (!on)
                _targetView?.ShowTouches(null);
        };
        AddChild(_followCheck);

        _resultBox = new VBoxContainer();
        _resultBox.AddThemeConstantOverride("separation", 6);
        AddChild(_resultBox);

        _resultLabel = new Label { AutowrapMode = TextServer.AutowrapMode.WordSmart, CustomMinimumSize = new Vector2(240f, 0f) };
        _resultBox.AddChild(_resultLabel);

        var resultRow = new HBoxContainer();
        resultRow.AddThemeConstantOverride("separation", 6);
        _resultBox.AddChild(resultRow);

        _saveButton = new Button { Text = "Save", SizeFlagsHorizontal = SizeFlags.ExpandFill };
        _saveButton.Pressed += OnSavePressed;
        resultRow.AddChild(_saveButton);

        var redo = new Button { Text = "Redo", SizeFlagsHorizontal = SizeFlags.ExpandFill };
        redo.Pressed += StartWizard;
        resultRow.AddChild(redo);

        var discard = new Button { Text = "Discard", SizeFlagsHorizontal = SizeFlags.ExpandFill };
        discard.Pressed += () =>
        {
            _result = null;
            _targetView?.ShowMessage("");
            Refresh();
        };
        resultRow.AddChild(discard);
    }

    private void RefreshScreens()
    {
        int previous = _screenPicker.ItemCount > 0 ? SelectedScreen : int.MinValue;
        _screenPicker.Clear();

        int count = DisplayServer.GetScreenCount();
        int primary = DisplayServer.GetPrimaryScreen();
        int mine = GetWindow().CurrentScreen;
        int firstOther = -1;

        for (int i = 0; i < count; i++)
        {
            Vector2I size = DisplayServer.ScreenGetSize(i);
            string label = $"Screen {i + 1}: {size.X}×{size.Y}";
            if (i == primary)
                label += ", primary";
            if (i == mine)
                label += ", this window";
            else if (firstOther < 0)
                firstOther = i;

            _screenPicker.AddItem(label, i);
        }

        _screenPicker.AddItem("Test window on this screen", TestWindowScreen);

        // Keep the previous choice; otherwise guess the projector is a screen this window isn't on.
        int select = _screenPicker.GetItemIndex(previous);
        if (select < 0)
            select = _screenPicker.GetItemIndex(firstOther >= 0 ? firstOther : TestWindowScreen);
        _screenPicker.Select(select);
    }

    /// <summary>Updates buttons and the status line to match the current state.</summary>
    private void Refresh()
    {
        bool canCalibrate = _streaming && _hasBaseline && !string.IsNullOrEmpty(_serial);

        _windowButton.Text = _targetWindow is null ? "Open target window" : "Close target window";
        _screenPicker.Disabled = _targetWindow is not null;

        if (_wizard is not null)
        {
            _startButton.Text = "Cancel calibration";
            _startButton.Disabled = false;
        }
        else
        {
            _startButton.Text = _calibration is null ? "Start calibration" : "Recalibrate";
            _startButton.Disabled = !canCalibrate;
        }

        _followCheck.Disabled = _calibration is null || _wizard is not null;
        _resultBox.Visible = _result is not null;

        if (_wizard is not null || _result is not null)
            return;

        string state = _calibration is null
            ? "Not calibrated."
            : $"Calibrated {_calibration.CalibratedAtUtc.ToLocalTime():g}. Centre check {_calibration.CentreErrorMm:0} mm.";

        string next = !_streaming ? " Connect the lidar to calibrate."
            : !_hasBaseline ? " Capture a baseline first, with the wall clear."
            : string.IsNullOrEmpty(_serial) ? " The lidar didn't report a serial number, so a calibration couldn't be saved."
            : _calibration is null ? " Pick the projector's screen, then start."
            : "";

        _status.Text = state + next;
    }

    // ------------------------------------------------------------------ target window

    private void OpenTargetWindow()
    {
        if (_targetWindow is not null)
            return;

        // Windows are drawn inside the game window unless the root says otherwise. This scene can be
        // opened from the main menu, so remember the setting and put it back afterwards.
        Window root = GetTree().Root;
        _embedSubwindowsBefore ??= root.GuiEmbedSubwindows;
        root.GuiEmbedSubwindows = false;

        int screen = SelectedScreen;
        bool onProjector = screen >= 0 && screen < DisplayServer.GetScreenCount();
        var window = new Window { Title = "Lidar calibration targets", Size = new Vector2I(960, 540) };

        if (onProjector)
        {
            // Open on that screen in Godot's fullscreen mode, so Godot and the OS size it to the
            // monitor. Sizing a borderless window from the reported screen size doesn't fit when the
            // OS scales the window differently.
            window.InitialPosition = Window.WindowInitialPosition.CenterOtherScreen;
            window.CurrentScreen = screen;
            window.Mode = Window.ModeEnum.Fullscreen;
            window.AlwaysOnTop = true;
            window.Unfocusable = true;
        }
        else
        {
            window.InitialPosition = Window.WindowInitialPosition.CenterMainWindowScreen;
        }

        window.CloseRequested += CloseTargetWindow;
        window.TreeExited += RestoreEmbedding;

        _targetView = new CalibrationTargetView();
        window.AddChild(_targetView);
        _targetWindow = window;
        AddChild(window);

        // In case it opened elsewhere, move it; a fullscreen window refits to its new screen.
        if (onProjector && window.CurrentScreen != screen)
            window.CurrentScreen = screen;

        // So you can see it opened on the right projector before starting.
        _targetView.ShowMessage("Lidar calibration target window");
        Refresh();
    }

    private void CloseTargetWindow()
    {
        if (_wizard is not null)
            StopWizard();

        _targetWindow?.QueueFree();
        _targetWindow = null;
        _targetView = null;
        Refresh();
    }

    private void RestoreEmbedding()
    {
        if (_embedSubwindowsBefore is { } before && IsInsideTree())
            GetTree().Root.GuiEmbedSubwindows = before;
        _embedSubwindowsBefore = null;
    }

    // ------------------------------------------------------------------ wizard

    private void StartWizard()
    {
        if (!_streaming || !_hasBaseline || string.IsNullOrEmpty(_serial))
            return;

        OpenTargetWindow();
        _result = null;
        _targetView?.ShowTouches(null);
        _wizard = new CalibrationWizard();
        CalibratingChanged?.Invoke(true);

        ShowWizardProgress();
        Refresh();
    }

    private void StopWizard()
    {
        _wizard = null;
        CalibratingChanged?.Invoke(false);
        _targetView?.ShowMessage("");
        Refresh();
    }

    private void ShowWizardProgress()
    {
        CalibrationWizard wizard = _wizard!;
        int current = wizard.CurrentTarget;
        int total = wizard.TargetsUv.Count;
        string name = current < total ? CalibrationWizard.TargetNames[current] : "";

        string message = wizard.Step switch
        {
            CalibrationStep.WaitingForRelease => "Got it. Let go.",
            CalibrationStep.Holding => "Hold still…",
            _ when wizard.TooManyTouches => "One hand at a time.",
            _ => $"Touch and hold the {name} target.",
        };

        _targetView?.ShowTargets(wizard.TargetsUv, current,
            wizard.Step == CalibrationStep.Holding ? wizard.HoldProgress : 0f, message);
        _status.Text = $"Target {Math.Min(current + 1, total)} of {total}: {message}";
    }

    private void FinishWizard()
    {
        CalibrationWizard wizard = _wizard!;
        _result = CalibrationSolver.Solve(_serial!, wizard.Points);
        _wizard = null;
        CalibratingChanged?.Invoke(false);

        ShowResult(_result);
        _targetView?.ShowMessage(_result.Calibration is null
            ? "Calibration failed. See the setup screen."
            : "Calibration captured. See the setup screen.");
        Refresh();
    }

    private void ShowResult(CalibrationSolveResult result)
    {
        _saveButton.Disabled = result.Calibration is null;

        if (result.Calibration is null)
        {
            _status.Text = "Calibration failed.";
            _resultLabel.Text = result.Error;
            _resultLabel.AddThemeColorOverride("font_color", PoorColor);
            return;
        }

        (string verdict, Color color) = result.Quality switch
        {
            CalibrationQuality.Good => ("Good. Save it, then check with the follow test.", GoodColor),
            CalibrationQuality.Fair => ("Usable. Save it and check the follow test; redo if dots land off your finger.", FairColor),
            _ => ("Poor: the centre touch was far from where the corners predicted. Redo it, touching the middle of each target.", PoorColor),
        };

        string[] shortNames = { "TL", "TR", "BR", "BL", "C" };
        var fit = new List<string>();
        for (int i = 0; i < result.ResidualsMm.Count; i++)
            fit.Add($"{shortNames[i]} {result.ResidualsMm[i]:0}");

        _status.Text = "Calibration captured.";
        _resultLabel.Text = $"Centre check: {result.CentreErrorMm:0} mm. {verdict}\nFit per target (mm): {string.Join(" · ", fit)}";
        _resultLabel.AddThemeColorOverride("font_color", color);
    }

    private void OnSavePressed()
    {
        if (_result?.Calibration is not { } calibration)
            return;

        _result = null;
        CalibrationAccepted?.Invoke(calibration);

        // The follow test is the real check, so start it straight away.
        _followCheck.ButtonPressed = true;
        _targetView?.ShowMessage("");
        Refresh();
    }

    private void ShowFollowTest(TouchFrame frame)
    {
        if (_targetView is null || _calibration is null)
            return;

        var dots = new List<(int Id, Vector2 Uv)>();
        foreach (TrackedTouch touch in frame.Touches)
        {
            if (touch.Confirmed && _calibration.TryMapToUv(touch.PositionMm, out Vector2 uv))
                dots.Add((touch.Id, uv));
        }

        _targetView.ShowTouches(dots);
    }
}
