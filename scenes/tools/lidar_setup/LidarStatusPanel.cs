using Godot;

namespace Zurd.Lidar;

/// <summary>
/// The three-stage connection checklist (connected, data flowing, healthy) plus live numbers.
/// Pure display: feed it a <see cref="LidarStatus"/> a few times a second.
/// </summary>
public partial class LidarStatusPanel : VBoxContainer
{
    private static readonly Color PendingColor = new(0.50f, 0.52f, 0.58f);
    private static readonly Color OkColor = new(0.30f, 0.78f, 0.40f);
    private static readonly Color WarningColor = new(0.95f, 0.70f, 0.20f);
    private static readonly Color FailedColor = new(0.90f, 0.30f, 0.30f);
    private static readonly Color DimTextColor = new(0.72f, 0.74f, 0.80f);

    private readonly StageRow[] _rows = new StageRow[3];
    private readonly Label[] _statValues = new Label[5];
    private Label _deviceLabel = null!;

    public override void _Ready()
    {
        AddThemeConstantOverride("separation", 10);

        _rows[0] = AddRow("1 · Connected");
        _rows[1] = AddRow("2 · Data flowing");
        _rows[2] = AddRow("3 · Healthy");

        _deviceLabel = new Label { AutowrapMode = TextServer.AutowrapMode.WordSmart };
        _deviceLabel.AddThemeColorOverride("font_color", DimTextColor);
        AddChild(_deviceLabel);

        var grid = new GridContainer { Columns = 2 };
        grid.AddThemeConstantOverride("h_separation", 16);
        AddChild(grid);

        string[] names = { "Points / s", "Rotations / s", "Points / rotation", "Last data", "Rotations seen" };
        for (int i = 0; i < names.Length; i++)
        {
            var name = new Label { Text = names[i] };
            name.AddThemeColorOverride("font_color", DimTextColor);
            grid.AddChild(name);

            _statValues[i] = new Label { Text = "—", HorizontalAlignment = HorizontalAlignment.Right };
            _statValues[i].SizeFlagsHorizontal = SizeFlags.ExpandFill;
            grid.AddChild(_statValues[i]);
        }
    }

    public void Update(LidarStatus status)
    {
        SetRow(_rows[0], status.Connection);
        SetRow(_rows[1], status.Data);
        SetRow(_rows[2], status.Health);

        if (status.Device is { } device)
        {
            string serial = device.Serial.Length > 8 ? "…" + device.Serial[^8..] : device.Serial;
            _deviceLabel.Text = $"Hardware rev {device.Hardware} · serial {serial}";
        }
        else
        {
            _deviceLabel.Text = "";
        }

        _statValues[0].Text = $"{status.PointsPerSecond:F0}";
        _statValues[1].Text = $"{status.RevolutionsPerSecond:F1}";
        _statValues[2].Text = $"{status.PointsPerRevolution:F0}";
        _statValues[3].Text = double.IsPositiveInfinity(status.SecondsSinceLastData)
            ? "never"
            : $"{status.SecondsSinceLastData:F2} s ago";
        _statValues[4].Text = $"{status.TotalRevolutions}";
    }

    private StageRow AddRow(string title)
    {
        var row = new HBoxContainer();
        row.AddThemeConstantOverride("separation", 10);
        AddChild(row);

        var dot = new ColorRect
        {
            Color = PendingColor,
            CustomMinimumSize = new Vector2(14f, 14f),
            SizeFlagsVertical = SizeFlags.ShrinkBegin,
        };
        row.AddChild(dot);

        var text = new VBoxContainer { SizeFlagsHorizontal = SizeFlags.ExpandFill };
        row.AddChild(text);

        text.AddChild(new Label { Text = title });

        var detail = new Label
        {
            Text = "—",
            AutowrapMode = TextServer.AutowrapMode.WordSmart,
            CustomMinimumSize = new Vector2(240f, 0f),
        };
        detail.AddThemeColorOverride("font_color", DimTextColor);
        text.AddChild(detail);

        return new StageRow(dot, detail);
    }

    private static void SetRow(StageRow row, LidarStage stage)
    {
        row.Dot.Color = stage.State switch
        {
            LidarStageState.Ok => OkColor,
            LidarStageState.Warning => WarningColor,
            LidarStageState.Failed => FailedColor,
            _ => PendingColor,
        };
        row.Detail.Text = stage.Detail;
    }

    private sealed class StageRow
    {
        public StageRow(ColorRect dot, Label detail)
        {
            Dot = dot;
            Detail = detail;
        }

        public ColorRect Dot { get; }
        public Label Detail { get; }
    }
}
