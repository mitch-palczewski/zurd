using Godot;
using Zurd.Lidar;

/// <summary>
/// The smallest useful lidar setup: connect, capture a baseline automatically, then print and
/// emit every touch. Set <see cref="Port"/> in the Inspector and run the scene with F6. Keep the
/// scan plane clear for the first few seconds while the baseline is captured.
/// </summary>
public partial class TestLidarTouch : Node
{
    [Signal]
    public delegate void TouchBeganEventHandler(int id, Vector2 positionMm);

    [Signal]
    public delegate void TouchEndedEventHandler(int id, double heldSec);

    [Export]
    public string Port { get; set; } = "COM3";

    private LidarDevice _device = null!;
    private TouchDetector _detector = null!;
    private long _lastSequence = -1;
    private bool _reportedFailure;

    public override void _Ready()
    {
        _device = new LidarDevice(new LidarDeviceOptions { Port = Port });
        _detector = new TouchDetector(new TouchDetectorOptions());

        // Runs on a worker thread; _Process watches the result.
        _ = _device.ConnectAsync();
    }

    public override void _ExitTree()
    {
        // Stops the motor and releases the port.
        _device?.Dispose();
    }

    public override void _Process(double delta)
    {
        if (_device.State == LidarConnectionState.Failed && !_reportedFailure)
        {
            _reportedFailure = true;
            GD.PushError($"[TestLidarTouch] {_device.LastError}");
        }

        if (!_device.TryGetNewScan(_lastSequence, out LidarScan? scan))
            return;

        _lastSequence = scan.Sequence;

        // The first scans after connecting become the baseline.
        if (_detector.Baseline is null && !_detector.IsCapturingBaseline)
        {
            GD.Print("Capturing baseline, keep the scan plane clear…");
            _detector.BeginBaselineCapture();
        }

        bool wasCapturing = _detector.IsCapturingBaseline;
        TouchFrame frame = _detector.Process(scan);
        if (wasCapturing && !_detector.IsCapturingBaseline)
            GD.Print("Baseline ready. Touch the wall.");

        foreach (TouchEvent evt in frame.Events)
        {
            if (evt.Kind == TouchEventKind.Began)
            {
                (float angle, float distance) = LidarGeometry.ToPolar(evt.PositionMm);
                GD.Print($"Touch #{evt.TouchId} began at {distance:0} mm, {angle:0}°");
                EmitSignal(SignalName.TouchBegan, evt.TouchId, evt.PositionMm);
            }
            else
            {
                GD.Print($"Touch #{evt.TouchId} ended after {evt.DurationSec:0.00} s");
                EmitSignal(SignalName.TouchEnded, evt.TouchId, evt.DurationSec);
            }
        }
    }
}
