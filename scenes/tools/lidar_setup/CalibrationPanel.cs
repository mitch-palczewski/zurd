using System;
using System.Collections.Generic;
using Godot;

namespace Zurd.Lidar;

/// <summary>
/// The calibration section of the setup scene. Picks the projector screen, opens the target window,
/// runs <see cref="CalibrationWizard"/>, solves with <see cref="CalibrationSolver"/>, and offers the
/// result both here and on the wall, as Save and Redo touch buttons. Saving and applying a
/// calibration is <see cref="LidarSetup"/>'s job, via <see cref="CalibrationAccepted"/>.
/// <para>
/// Esc cancels the wizard or else closes the target window; Backspace steps back one target. Both
/// work while the target window covers this one, because that window never takes focus.
/// </para>
/// </summary>
public partial class CalibrationPanel : VBoxContainer
{
    /// <summary>Screen id for a plain test window on the setup window's own screen.</summary>
    private const int TestWindowScreen = -1;

    /// <summary>The test window's item id in the screen picker. Not -1: OptionButton reads an id of -1 as "use the index".</summary>
    private const int TestWindowItemId = 1000;

    private const string WizardKeys = "Keyboard: Esc cancels · Backspace goes back one target";
    private const string WindowKeys = "Keyboard: Esc closes this window";

    private static readonly Color DimTextColor = new(0.72f, 0.74f, 0.80f);
    private static readonly Color GoodColor = new(0.30f, 0.78f, 0.40f);
    private static readonly Color FairColor = new(0.95f, 0.70f, 0.20f);
    private static readonly Color PoorColor = new(0.90f, 0.30f, 0.30f);

    // Touch buttons on the wall once the wizard has finished. Large, so even a poor calibration
    // places a touch on the right one.
    private static readonly WallButton SaveOnWall = new("Save", new Rect2(0.15f, 0.55f, 0.3f, 0.25f));
    private static readonly WallButton RedoOnWall = new("Redo", new Rect2(0.55f, 0.55f, 0.3f, 0.25f));
    private static readonly WallButton[] ReviewButtons = { SaveOnWall, RedoOnWall };

    /// <summary>After a failed solve there's no calibration to place a touch with, so a touch anywhere counts.</summary>
    private static readonly WallButton[] RetryButtons = { new("Redo", new Rect2(0.35f, 0.55f, 0.3f, 0.25f)) };

    private Label _status = null!;
    private Label _sensorLabel = null!;
    private Label _windowInfo = null!;
    private OptionButton _screenPicker = null!;
    private Button _windowButton = null!;
    private Button _startButton = null!;
    private Button _stepBackButton = null!;
    private CheckBox _followCheck = null!;
    private VBoxContainer _resultBox = null!;
    private Label _resultLabel = null!;
    private Button _saveButton = null!;

    private Window? _targetWindow;
    private CalibrationTargetView? _targetView;
    private bool? _embedSubwindowsBefore;

    private CalibrationWizard? _wizard;
    private CalibrationSolveResult? _result;
    private WallChoice? _review;
    private WallCalibration? _calibration;
    private SensorCheck? _sensorCheck;
    private bool _calibratingShown;

    private bool _streaming;
    private bool _hasBaseline;
    private string? _serial;

    /// <summary>A solved calibration the user chose to keep.</summary>
    public event Action<WallCalibration>? CalibrationAccepted;

    /// <summary>
    /// Raised when <see cref="IsCalibrating"/> changes. While it's true, detection should ignore any
    /// old calibrated area: if the sensor has moved, the old area could hide the touches needed.
    /// </summary>
    public event Action<bool>? CalibratingChanged;

    /// <summary>True from the start of the wizard until its result is saved, discarded or redone.</summary>
    public bool IsCalibrating => _wizard is not null || _result is not null;

    /// <summary>Screen index the targets go on, or -1 for a test window on this screen.</summary>
    public int SelectedScreen
    {
        get
        {
            int id = _screenPicker.Selected < 0 ? TestWindowItemId : _screenPicker.GetItemId(_screenPicker.Selected);
            return id == TestWindowItemId ? TestWindowScreen : id;
        }
    }

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

    public override void _ShortcutInput(InputEvent @event)
    {
        if (@event is not InputEventKey { Pressed: true, Echo: false } key)
            return;

        bool handled = key.Keycode switch
        {
            Key.Escape => BackOut(),
            Key.Backspace => StepBack(),
            _ => false,
        };

        if (handled)
            GetViewport().SetInputAsHandled();
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

    /// <summary>How the current baseline compares with the one saved with the calibration; null hides the line.</summary>
    public void SetSensorCheck(SensorCheck? check)
    {
        _sensorCheck = check;
        if (check is not null)
        {
            (string text, Color color) = DescribeSensorCheck(check);
            _sensorLabel.Text = text;
            _sensorLabel.AddThemeColorOverride("font_color", color);
        }

        Refresh();
    }

    /// <summary>Selects the screen used last time for this lidar, if it still exists.</summary>
    public void PreferScreen(int? screen)
    {
        if (screen is null || _targetWindow is not null)
            return;

        int index = ItemIndexOf(screen.Value);
        if (index >= 0)
            _screenPicker.Select(index);
    }

    private int ItemIndexOf(int screen) => _screenPicker.GetItemIndex(screen == TestWindowScreen ? TestWindowItemId : screen);

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
        else if (_review is not null)
        {
            _review.Update(frame);
            if (_review.Chosen == SaveOnWall)
                OnSavePressed();
            else if (_review.Chosen is not null)
                StartWizard();
            else
                ShowReview();
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

        _sensorLabel = new Label
        {
            AutowrapMode = TextServer.AutowrapMode.WordSmart,
            CustomMinimumSize = new Vector2(240f, 0f),
            Visible = false,
        };
        AddChild(_sensorLabel);

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

        _stepBackButton = new Button
        {
            Text = "Back one target",
            Visible = false,
            TooltipText = "Forget the last captured target and touch it again. Backspace does the same.",
        };
        _stepBackButton.Pressed += () => StepBack();
        AddChild(_stepBackButton);

        var keys = new Label
        {
            Text = "Esc cancels calibration or closes the target window; Backspace steps back one target. " +
                "Both work while the target window covers this screen.",
            AutowrapMode = TextServer.AutowrapMode.WordSmart,
            CustomMinimumSize = new Vector2(240f, 0f),
        };
        keys.AddThemeColorOverride("font_color", DimTextColor);
        AddChild(keys);

        _followCheck = new CheckBox
        {
            Text = "Follow test: show touches on the wall",
            TooltipText = "Draws a dot on the projector under every touch. It should land under your finger.",
        };
        _followCheck.Toggled += on =>
        {
            if (on)
                return;

            _targetView?.ShowTouches(null);
            _targetView?.ShowMessage("");
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
            _review = null;
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

        _screenPicker.AddItem("Test window on this screen", TestWindowItemId);

        // Keep the previous choice; otherwise guess the projector is a screen this window isn't on.
        int select = ItemIndexOf(previous);
        if (select < 0)
            select = ItemIndexOf(firstOther >= 0 ? firstOther : TestWindowScreen);
        _screenPicker.Select(select);
    }

    /// <summary>Updates buttons and the status line to match the current state.</summary>
    private void Refresh()
    {
        bool canCalibrate = _streaming && _hasBaseline && !string.IsNullOrEmpty(_serial);
        bool calibrating = IsCalibrating;

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

        _stepBackButton.Visible = _wizard is not null;
        _stepBackButton.Disabled = _wizard is not { CanStepBack: true };
        _followCheck.Disabled = _calibration is null || calibrating;
        _resultBox.Visible = _result is not null;
        _targetView?.SetFooter(_wizard is not null ? WizardKeys : WindowKeys);

        // The check is about the saved calibration, so it steps aside while a new one is under way.
        _sensorLabel.Visible = _sensorCheck is not null && _calibration is not null && !calibrating;

        if (calibrating != _calibratingShown)
        {
            _calibratingShown = calibrating;
            CalibratingChanged?.Invoke(calibrating);
        }

        if (calibrating)
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

    private static (string Text, Color Color) DescribeSensorCheck(SensorCheck check)
    {
        string changed = $"{check.ChangedShare * 100f:0}% of directions changed";
        string details = float.IsNaN(check.ShiftMm)
            ? changed
            : $"shifted about {check.ShiftMm:0} mm, turned {check.TurnedDeg:0.0}°, {changed}";

        return check.Verdict switch
        {
            SensorVerdict.Unchanged => ($"Sensor check: matches the calibration ({details}).", GoodColor),
            SensorVerdict.Moved => ($"The sensor seems to have moved since it was calibrated ({details}). " +
                "Check with the follow test, and recalibrate if the dots land off your finger.", PoorColor),
            _ => ("Sensor check: too little in view to compare with the calibration.", DimTextColor),
        };
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

        // A result stays on this screen to save or discard; only the wall's buttons go.
        _review = null;
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
        _review = null;
        _targetView?.ShowTouches(null);
        _wizard = new CalibrationWizard();

        ShowWizardProgress();
        Refresh();
    }

    private void StopWizard()
    {
        _wizard = null;
        _targetView?.ShowMessage("Calibration cancelled.");
        Refresh();
    }

    /// <summary>Esc: cancels the wizard, or else closes the target window. False if there was nothing to back out of.</summary>
    private bool BackOut()
    {
        if (_wizard is not null)
            StopWizard();
        else if (_targetWindow is not null)
            CloseTargetWindow();
        else
            return false;

        return true;
    }

    /// <summary>Backspace or the button: drops the last captured target. False if there was nothing to drop.</summary>
    private bool StepBack()
    {
        if (_wizard is null || !_wizard.StepBack())
            return false;

        ShowWizardProgress();
        Refresh();
        return true;
    }

    private void ShowWizardProgress()
    {
        CalibrationWizard wizard = _wizard!;
        int current = wizard.CurrentTarget;
        int total = wizard.TargetsUv.Count;
        string name = current < total ? CalibrationWizard.TargetNames[current] : "";

        string message = wizard.Step switch
        {
            CalibrationStep.Holding => "Hold still…",
            CalibrationStep.WaitingForRelease when wizard.Notice == CalibrationNotice.Rejected =>
                $"{wizard.Rejection} Let go, then try again.",
            CalibrationStep.WaitingForRelease => "Got it. Let go.",
            _ when wizard.TooManyTouches => "One hand at a time.",
            _ when wizard.Notice == CalibrationNotice.Rejected => $"{wizard.Rejection} Touch and hold the {name} target.",
            _ when wizard.Notice == CalibrationNotice.SteppedBack => $"Back to the {name} target. Touch and hold it.",
            _ => $"Touch and hold the {name} target.",
        };

        _targetView?.ShowTargets(wizard.TargetsUv, current,
            wizard.Step == CalibrationStep.Holding ? wizard.HoldProgress : 0f, message);
        _stepBackButton.Disabled = !wizard.CanStepBack;

        string status = $"Target {Math.Min(current + 1, total)} of {total}: {message}";
        if (wizard.IgnoredTouches > 0)
        {
            string ignored = wizard.IgnoredTouches == 1 ? "1 touch that was" : $"{wizard.IgnoredTouches} touches that were";
            status += $"\nIgnoring {ignored} already down when this target came up. If nobody is touching there, " +
                "something new is in the scan plane: recapture the baseline once it's clear.";
        }

        _status.Text = status;
    }

    private void FinishWizard()
    {
        CalibrationWizard wizard = _wizard!;
        _result = CalibrationSolver.Solve(_serial!, wizard.Points);
        _wizard = null;

        // The person at the wall can keep it or start again from there.
        _review = new WallChoice(_result.Calibration is null ? RetryButtons : ReviewButtons, _result.Calibration);

        ShowResult(_result);
        ShowReview();
        Refresh();
    }

    private void ShowResult(CalibrationSolveResult result)
    {
        _saveButton.Disabled = result.Calibration is null;

        if (result.Calibration is null)
        {
            _status.Text = "Calibration failed. Redo it here or by touching the wall.";
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

        _status.Text = "Calibration captured. Save or redo it here, or with the buttons on the wall.";
        _resultLabel.Text = $"Centre check: {result.CentreErrorMm:0} mm. {verdict}\nFit per target (mm): {string.Join(" · ", fit)}";
        _resultLabel.AddThemeColorOverride("font_color", color);
    }

    /// <summary>The result on the wall, with its touch buttons.</summary>
    private void ShowReview()
    {
        if (_targetView is null || _review is null || _result is null)
            return;

        string message = _result.Calibration is null
            ? $"Calibration failed. {_result.Error}\nTouch and hold anywhere to start again."
            : $"Centre check: {_result.CentreErrorMm:0} mm, {QualityWord(_result.Quality)}.\n" +
              "Hold Save to keep this calibration, or Redo to start again.";

        _targetView.ShowChoice(message, _review.Buttons, _review.HeldButton, _review.Progress);
    }

    private static string QualityWord(CalibrationQuality quality) => quality switch
    {
        CalibrationQuality.Good => "good",
        CalibrationQuality.Fair => "usable",
        _ => "poor: better to redo it",
    };

    private void OnSavePressed()
    {
        if (_result?.Calibration is not { } calibration)
            return;

        _result = null;
        _review = null;
        CalibrationAccepted?.Invoke(calibration);

        // The follow test is the real check, so start it straight away.
        _followCheck.ButtonPressed = true;
        _targetView?.ShowMessage("Saved. Touch anywhere: the dot should land under your finger.");
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
