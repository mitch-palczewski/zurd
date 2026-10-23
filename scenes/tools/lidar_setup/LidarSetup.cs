using System;
using System.Collections.Generic;
using Godot;
using ScanMode = RpLidar.NET.Entities.ScanMode;

namespace Zurd.Lidar;

/// <summary>
/// Utility scene for bringing a lidar up: pick the port, connect, and watch the sweep plus a
/// three-stage status checklist; then capture a baseline and watch touches being detected.
/// Run it on its own (F6); it is not part of the game flow.
/// <para>
/// All device logic lives in <see cref="LidarDevice"/> and all detection logic in
/// <see cref="TouchDetector"/>. This node only builds the controls and shows what they report.
/// </para>
/// </summary>
public partial class LidarSetup : Control
{
    private const double StatusRefreshSec = 0.25;
    private const double PwmApplyDelaySec = 0.4;
    private const int EventLogLines = 12;

    private LidarDevice _device = null!;
    private TouchDetector _detector = null!;
    private LidarStatusPanel _statusPanel = null!;
    private LidarPointView _view = null!;

    private OptionButton _portPicker = null!;
    private OptionButton _modePicker = null!;
    private Button _connectButton = null!;
    private HSlider _pwmSlider = null!;
    private Label _pwmValue = null!;
    private HSlider _rangeSlider = null!;
    private Label _rangeValue = null!;

    private Button _captureButton = null!;
    private Button _clearBaselineButton = null!;
    private Label _baselineLabel = null!;
    private Label _touchSummary = null!;
    private Label _eventLog = null!;
    private readonly List<string> _eventLines = new();

    private bool _hasPorts;
    private long _lastSequence = -1;
    private double _statusTimer;
    private double _pwmCountdown = -1.0;
    private LidarConnectionState _shownState = LidarConnectionState.Disconnected;

    public override void _Ready()
    {
        _device = new LidarDevice(new LidarDeviceOptions());
        _detector = new TouchDetector(new TouchDetectorOptions());

        BuildUi();
        RefreshPorts();
        ShowState(LidarConnectionState.Disconnected);
    }

    public override void _ExitTree()
    {
        // Stops the motor and releases the serial port. Without this the lidar keeps spinning.
        _device?.Dispose();
    }

    public override void _Process(double delta)
    {
        if (_device.TryGetNewScan(_lastSequence, out LidarScan? scan))
        {
            _lastSequence = scan.Sequence;

            TouchFrame frame = _detector.Process(scan);
            _view.Baseline = _detector.Baseline;
            _view.Detection = frame;
            _view.Scan = scan;

            LogEvents(frame);
            ShowTouchSummary(frame);
            RefreshBaselineControls();
        }

        // The motor-speed slider applies once it has been still for a moment. Each change makes
        // the driver flush its input buffer, so we don't send one per pixel of dragging.
        if (_pwmCountdown >= 0.0)
        {
            _pwmCountdown -= delta;
            if (_pwmCountdown < 0.0)
            {
                _pwmCountdown = -1.0;
                _ = _device.SetMotorPwmAsync((ushort)_pwmSlider.Value);
            }
        }

        _statusTimer += delta;
        if (_statusTimer >= StatusRefreshSec)
        {
            _statusTimer = 0.0;

            LidarStatus status = _device.GetStatus();
            _statusPanel.Update(status);

            if (status.State != _shownState)
            {
                if (status.State == LidarConnectionState.Failed)
                    GD.PushWarning($"[LidarSetup] {status.Connection.Detail}");

                ShowState(status.State);
            }
        }
    }

    // ------------------------------------------------------------------ UI construction

    private void BuildUi()
    {
        var margin = new MarginContainer();
        margin.SetAnchorsPreset(LayoutPreset.FullRect);
        foreach (string side in new[] { "margin_left", "margin_top", "margin_right", "margin_bottom" })
            margin.AddThemeConstantOverride(side, 12);
        AddChild(margin);

        var root = new HBoxContainer();
        root.AddThemeConstantOverride("separation", 12);
        margin.AddChild(root);

        // Left column: controls and status. Scrolls if the window is short.
        var scroll = new ScrollContainer
        {
            CustomMinimumSize = new Vector2(370f, 0f),
            HorizontalScrollMode = ScrollContainer.ScrollMode.Disabled,
        };
        root.AddChild(scroll);

        var scrollPad = new MarginContainer { SizeFlagsHorizontal = SizeFlags.ExpandFill };
        scrollPad.AddThemeConstantOverride("margin_right", 12);
        scroll.AddChild(scrollPad);

        var left = new VBoxContainer { SizeFlagsHorizontal = SizeFlags.ExpandFill };
        left.AddThemeConstantOverride("separation", 10);
        scrollPad.AddChild(left);

        var title = new Label { Text = "LiDAR setup" };
        title.AddThemeFontSizeOverride("font_size", 22);
        left.AddChild(title);

        // -- Connection controls
        left.AddChild(MakeHeading("Connection"));

        var portRow = new HBoxContainer();
        portRow.AddThemeConstantOverride("separation", 6);
        left.AddChild(portRow);

        _portPicker = new OptionButton
        {
            SizeFlagsHorizontal = SizeFlags.ExpandFill,
            TooltipText = "Serial port the lidar's USB adapter appears as.",
        };
        portRow.AddChild(_portPicker);

        var refresh = new Button { Text = "Refresh", TooltipText = "Re-scan for serial ports." };
        refresh.Pressed += RefreshPorts;
        portRow.AddChild(refresh);

        left.AddChild(MakeDimLabel("Scan mode"));
        _modePicker = new OptionButton
        {
            TooltipText = "Sensitivity is the driver's default. If no data arrives, reconnect with Boost, then Standard.",
        };
        _modePicker.AddItem("Sensitivity (default)", (int)ScanMode.Sensitivity);
        _modePicker.AddItem("Boost", (int)ScanMode.Boost);
        _modePicker.AddItem("Standard", (int)ScanMode.Standard);
        left.AddChild(_modePicker);

        left.AddChild(MakeDimLabel("Motor speed (PWM)"));
        var pwmRow = new HBoxContainer();
        pwmRow.AddThemeConstantOverride("separation", 8);
        left.AddChild(pwmRow);

        _pwmSlider = new HSlider
        {
            MinValue = 200,
            MaxValue = 1023,
            Step = 10,
            Value = _device.Options.MotorPwm,
            SizeFlagsHorizontal = SizeFlags.ExpandFill,
            TooltipText = "Higher is faster. Applies a moment after you stop dragging.",
        };
        _pwmSlider.ValueChanged += value =>
        {
            _pwmValue.Text = $"{(int)value}";
            _pwmCountdown = PwmApplyDelaySec;
        };
        pwmRow.AddChild(_pwmSlider);

        _pwmValue = new Label { Text = $"{_device.Options.MotorPwm}", CustomMinimumSize = new Vector2(40f, 0f) };
        pwmRow.AddChild(_pwmValue);

        _connectButton = new Button { Text = "Connect" };
        _connectButton.Pressed += OnConnectPressed;
        left.AddChild(_connectButton);

        // -- Status
        left.AddChild(new HSeparator());
        left.AddChild(MakeHeading("Status"));
        _statusPanel = new LidarStatusPanel();
        left.AddChild(_statusPanel);

        // -- Touch detection
        left.AddChild(new HSeparator());
        left.AddChild(MakeHeading("Touch detection"));

        _baselineLabel = MakeDimLabel("");
        _baselineLabel.AutowrapMode = TextServer.AutowrapMode.WordSmart;
        _baselineLabel.CustomMinimumSize = new Vector2(240f, 0f);
        left.AddChild(_baselineLabel);

        var baselineRow = new HBoxContainer();
        baselineRow.AddThemeConstantOverride("separation", 6);
        left.AddChild(baselineRow);

        _captureButton = new Button
        {
            Text = "Capture baseline",
            SizeFlagsHorizontal = SizeFlags.ExpandFill,
            TooltipText = "Records what the lidar sees with nobody touching. Takes a few seconds; keep the scan plane clear.",
        };
        _captureButton.Pressed += OnCapturePressed;
        baselineRow.AddChild(_captureButton);

        _clearBaselineButton = new Button { Text = "Clear", TooltipText = "Forget the baseline and stop detecting." };
        _clearBaselineButton.Pressed += OnClearBaselinePressed;
        baselineRow.AddChild(_clearBaselineButton);

        TouchDetectorOptions touch = _detector.Options;
        var settings = new GridContainer { Columns = 2 };
        settings.AddThemeConstantOverride("h_separation", 12);
        left.AddChild(settings);

        AddSetting(settings, "Min depth change", "mm", 10, 500, 5, touch.MinDepthChangeMm,
            v => touch.MinDepthChangeMm = (float)v,
            "How much closer than the baseline a point must be to count. Raise it if pink points flicker along the baseline.");
        AddSetting(settings, "Max range", "mm", 500, 12000, 100, touch.MaxRangeMm,
            v => touch.MaxRangeMm = (float)v,
            "Ignore anything farther than this from the sensor.");
        AddSetting(settings, "Cluster gap", "mm", 10, 300, 5, touch.ClusterGapMm,
            v => touch.ClusterGapMm = (float)v,
            "Points closer together than this belong to the same blob. Raise it if one hand splits into several touches.");
        AddSetting(settings, "Min points", "", 1, 20, 1, touch.MinPointsPerBlob,
            v => touch.MinPointsPerBlob = (int)v,
            "Blobs with fewer points are ignored as noise.");
        AddSetting(settings, "Max blob width", "mm", 50, 2000, 10, touch.MaxBlobWidthMm,
            v => touch.MaxBlobWidthMm = (float)v,
            "Wider blobs (a body, a chair) are not touches. They show as faint rings.");
        AddSetting(settings, "Confirm after", "rot.", 1, 5, 1, touch.ConfirmRotations,
            v => touch.ConfirmRotations = (int)v,
            "Rotations in a row a blob must appear before it counts. 1 reacts fastest; 2 ignores one-rotation blips.");

        _touchSummary = new Label { Text = "—" };
        left.AddChild(_touchSummary);

        left.AddChild(MakeDimLabel("Events, newest first"));
        _eventLog = new Label { Text = "—" };
        left.AddChild(_eventLog);

        // -- View controls
        left.AddChild(new HSeparator());
        left.AddChild(MakeHeading("View"));

        _view = new LidarPointView { SizeFlagsHorizontal = SizeFlags.ExpandFill, SizeFlagsVertical = SizeFlags.ExpandFill };

        left.AddChild(MakeDimLabel("Range shown"));
        var rangeRow = new HBoxContainer();
        rangeRow.AddThemeConstantOverride("separation", 8);
        left.AddChild(rangeRow);

        _rangeSlider = new HSlider
        {
            MinValue = 300,
            MaxValue = 12000,
            Step = 100,
            Value = _view.RangeMm,
            SizeFlagsHorizontal = SizeFlags.ExpandFill,
        };
        _rangeSlider.ValueChanged += value => _view.RangeMm = (float)value;
        rangeRow.AddChild(_rangeSlider);

        _rangeValue = new Label { Text = FormatRange(_view.RangeMm), CustomMinimumSize = new Vector2(52f, 0f) };
        rangeRow.AddChild(_rangeValue);

        _view.RangeChanged += mm =>
        {
            _rangeSlider.SetValueNoSignal(mm);
            _rangeValue.Text = FormatRange(mm);
        };

        left.AddChild(MakeDimLabel("Rotate picture"));
        var rotation = new SpinBox
        {
            MinValue = -180,
            MaxValue = 180,
            Step = 1,
            Value = 0,
            Suffix = "°",
            TooltipText = "Turn the picture so the wall's top is up. Display only for now.",
        };
        rotation.ValueChanged += value => _view.AngleOffsetDeg = (float)value;
        left.AddChild(rotation);

        var mirror = new CheckBox
        {
            Text = "Mirror left/right",
            TooltipText = "Flip the sweep direction if the picture looks reversed.",
        };
        mirror.Toggled += on => _view.Mirror = on;
        left.AddChild(mirror);

        // Right: the point view.
        root.AddChild(_view);
    }

    private static Label MakeHeading(string text)
    {
        var label = new Label { Text = text };
        label.AddThemeFontSizeOverride("font_size", 17);
        return label;
    }

    private static Label MakeDimLabel(string text)
    {
        var label = new Label { Text = text };
        label.AddThemeColorOverride("font_color", new Color(0.72f, 0.74f, 0.80f));
        return label;
    }

    /// <summary>Adds a label and a spin box to a two-column grid; <paramref name="apply"/> runs on every change.</summary>
    private static void AddSetting(GridContainer grid, string name, string suffix, double min, double max, double step,
        double value, Action<double> apply, string tooltip)
    {
        grid.AddChild(MakeDimLabel(name));

        var spin = new SpinBox
        {
            MinValue = min,
            MaxValue = max,
            Step = step,
            Value = value,
            Suffix = suffix,
            SizeFlagsHorizontal = SizeFlags.ExpandFill,
            TooltipText = tooltip,
        };
        spin.ValueChanged += v => apply(v);
        grid.AddChild(spin);
    }

    private static string FormatRange(float mm) => mm >= 1000f ? $"{mm / 1000f:0.0} m" : $"{mm:0} mm";

    // ------------------------------------------------------------------ behaviour

    private void RefreshPorts()
    {
        string? previous = _hasPorts && _portPicker.ItemCount > 0
            ? _portPicker.GetItemText(_portPicker.Selected)
            : null;

        _portPicker.Clear();
        string[] ports = LidarDevice.ListPorts();
        _hasPorts = ports.Length > 0;

        if (!_hasPorts)
        {
            _portPicker.AddItem("(no serial ports found)");
            _portPicker.SetItemDisabled(0, true);
            return;
        }

        int select = ports.Length - 1;
        for (int i = 0; i < ports.Length; i++)
        {
            _portPicker.AddItem(ports[i]);
            if (ports[i] == previous)
                select = i;
        }

        _portPicker.Select(select);
    }

    private void OnConnectPressed()
    {
        if (_device.State == LidarConnectionState.Streaming)
        {
            _ = _device.DisconnectAsync();
            return;
        }

        if (!_hasPorts)
        {
            RefreshPorts();
            return;
        }

        LidarDeviceOptions options = _device.Options;
        string port = _portPicker.GetItemText(_portPicker.Selected);

        // A baseline belongs to one sensor in one spot, so it doesn't survive a port change.
        if (port != options.Port)
        {
            _detector.ClearBaseline();
            _view.Baseline = null;
        }

        options.Port = port;
        options.ScanMode = (ScanMode)_modePicker.GetItemId(_modePicker.Selected);
        options.MotorPwm = (ushort)_pwmSlider.Value;

        _ = _device.ConnectAsync();
    }

    private void OnCapturePressed()
    {
        _detector.BeginBaselineCapture();
        _view.Detection = null;
        RefreshBaselineControls();
    }

    private void OnClearBaselinePressed()
    {
        _detector.ClearBaseline();
        _view.Baseline = null;
        _view.Detection = null;
        _touchSummary.Text = "—";
        RefreshBaselineControls();
    }

    /// <summary>Updates the button, pickers and view to match a connection state.</summary>
    private void ShowState(LidarConnectionState state)
    {
        _shownState = state;

        bool idle = state is LidarConnectionState.Disconnected or LidarConnectionState.Failed;
        _portPicker.Disabled = !idle;
        _modePicker.Disabled = !idle;

        switch (state)
        {
            case LidarConnectionState.Streaming:
                _connectButton.Text = "Disconnect";
                _connectButton.Disabled = false;
                break;

            case LidarConnectionState.Connecting:
            case LidarConnectionState.Stopping:
                _connectButton.Text = "Working…";
                _connectButton.Disabled = true;
                break;

            default:
                _connectButton.Text = _hasPorts ? "Connect" : "Look for ports";
                _connectButton.Disabled = false;
                break;
        }

        if (idle)
        {
            // Keep the baseline (same sensor, same spot), but drop anything half-done.
            _detector.CancelBaselineCapture();
            _detector.ResetTracking();
            _view.Scan = null;
            _view.Detection = null;
            _touchSummary.Text = "—";
            _lastSequence = -1;
        }

        RefreshBaselineControls();
    }

    private void RefreshBaselineControls()
    {
        LidarBaseline? baseline = _detector.Baseline;

        if (_detector.IsCapturingBaseline)
        {
            _captureButton.Text = $"Capturing… {_detector.BaselineProgress * 100f:0}%";
            _captureButton.Disabled = true;
            _baselineLabel.Text = "Keep the scan plane clear until the capture finishes.";
        }
        else
        {
            _captureButton.Text = baseline is null ? "Capture baseline" : "Recapture baseline";
            _captureButton.Disabled = _device.State != LidarConnectionState.Streaming;
            _baselineLabel.Text = baseline is null
                ? "No baseline. Connect, make sure nothing is in the scan plane, then capture."
                : $"Baseline from {baseline.Rotations} rotations. A surface was seen in " +
                  $"{baseline.CoveredBins * 100 / baseline.BinCount}% of directions.";
        }

        _clearBaselineButton.Disabled = baseline is null && !_detector.IsCapturingBaseline;
    }

    private void ShowTouchSummary(TouchFrame frame)
    {
        if (_detector.IsCapturingBaseline)
            _touchSummary.Text = "Capturing baseline…";
        else if (_detector.Baseline is null)
            _touchSummary.Text = "Detection is off until a baseline is captured.";
        else
            _touchSummary.Text = $"{frame.ConfirmedCount} touching · {frame.Blobs.Count} blobs this rotation";
    }

    private void LogEvents(TouchFrame frame)
    {
        if (frame.Events.Count == 0)
            return;

        foreach (TouchEvent evt in frame.Events)
        {
            (float angle, float distance) = LidarGeometry.ToPolar(evt.PositionMm);
            string line = evt.Kind == TouchEventKind.Began
                ? $"#{evt.TouchId} down · {distance / 1000f:0.00} m · {angle:0}°"
                : $"#{evt.TouchId} up · held {evt.DurationSec:0.00} s";
            _eventLines.Insert(0, $"{DateTime.Now:HH:mm:ss.f}  {line}");
        }

        if (_eventLines.Count > EventLogLines)
            _eventLines.RemoveRange(EventLogLines, _eventLines.Count - EventLogLines);

        _eventLog.Text = string.Join("\n", _eventLines);
    }
}
