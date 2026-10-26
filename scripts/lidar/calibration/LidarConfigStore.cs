using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using Godot;

namespace Zurd.Lidar;

/// <summary>Everything remembered about one lidar, keyed by its serial number.</summary>
public sealed class LidarConfigEntry
{
    public WallCalibration? Calibration { get; set; }

    /// <summary>Display only: how the setup scene's 2D view is turned. See <see cref="LidarGeometry.ToLocal"/>.</summary>
    public float AngleOffsetDeg { get; set; }

    /// <summary>Display only: whether the setup scene's 2D view is mirrored.</summary>
    public bool Mirror { get; set; }

    /// <summary>Screen the calibration targets were shown on, so the setup scene can preselect it.</summary>
    public int? TargetScreen { get; set; }
}

/// <summary>
/// Reads and writes the lidar config file (normally <c>user://lidar_config.json</c>, passed in as
/// an absolute path). Entries are keyed by lidar serial number, because COM port names can change
/// when a lidar is replugged. Plain C#, main thread only.
/// </summary>
public sealed class LidarConfigStore
{
    private const int FileVersion = 1;

    private static readonly JsonSerializerOptions Json = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
    };

    private readonly Dictionary<string, LidarConfigEntry> _entries = new();

    public LidarConfigStore(string path)
    {
        Path = path;
        Load();
    }

    public string Path { get; }

    /// <summary>Why the file couldn't be read, or null. An unreadable file is copied to <c>.broken</c> first.</summary>
    public string? LoadError { get; private set; }

    public LidarConfigEntry? Get(string serial) => _entries.GetValueOrDefault(serial);

    public LidarConfigEntry GetOrCreate(string serial)
    {
        if (!_entries.TryGetValue(serial, out LidarConfigEntry? entry))
        {
            entry = new LidarConfigEntry();
            _entries[serial] = entry;
        }

        return entry;
    }

    /// <summary>Writes every entry. Writes a temporary file first, so a crash can't leave half a file.</summary>
    public bool Save(out string? error)
    {
        try
        {
            var file = new FileDto
            {
                Version = FileVersion,
                Lidars = _entries.ToDictionary(e => e.Key, e => ToDto(e.Value)),
            };

            string? directory = System.IO.Path.GetDirectoryName(Path);
            if (!string.IsNullOrEmpty(directory))
                Directory.CreateDirectory(directory);

            string temp = Path + ".tmp";
            File.WriteAllText(temp, JsonSerializer.Serialize(file, Json));
            File.Move(temp, Path, overwrite: true);

            error = null;
            return true;
        }
        catch (Exception e)
        {
            error = $"Could not save {Path}: {e.Message}";
            return false;
        }
    }

    private void Load()
    {
        if (!File.Exists(Path))
            return;

        try
        {
            FileDto? file = JsonSerializer.Deserialize<FileDto>(File.ReadAllText(Path), Json);
            if (file?.Lidars is null)
                return;

            foreach ((string serial, EntryDto dto) in file.Lidars)
                _entries[serial] = FromDto(serial, dto);
        }
        catch (Exception e)
        {
            _entries.Clear();
            LoadError = $"Could not read {Path} ({e.Message}). Starting with no saved calibrations; " +
                "the old file was copied to .broken.";
            try
            {
                File.Copy(Path, Path + ".broken", overwrite: true);
            }
            catch (Exception)
            {
                // Nothing more to do; the message above still explains what happened.
            }
        }
    }

    // ------------------------------------------------------------------ file format

    private static EntryDto ToDto(LidarConfigEntry entry)
    {
        WallCalibration? cal = entry.Calibration;
        return new EntryDto
        {
            AngleOffsetDeg = entry.AngleOffsetDeg,
            Mirror = entry.Mirror,
            TargetScreen = entry.TargetScreen,
            Calibration = cal is null ? null : new CalibrationDto
            {
                LidarToUv = cal.LidarToUv.ToArray(),
                Points = cal.Points.Select(p => new PointDto
                {
                    TargetUv = new[] { p.TargetUv.X, p.TargetUv.Y },
                    MeasuredMm = new[] { p.MeasuredMm.X, p.MeasuredMm.Y },
                }).ToArray(),
                CentreErrorMm = cal.CentreErrorMm,
                CalibratedAtUtc = cal.CalibratedAtUtc,
            },
        };
    }

    private static LidarConfigEntry FromDto(string serial, EntryDto dto)
    {
        WallCalibration? calibration = null;
        if (dto.Calibration is { LidarToUv.Length: 9 } c)
        {
            CalibrationPoint[] points = (c.Points ?? Array.Empty<PointDto>())
                .Select(p => new CalibrationPoint(ToVector(p.TargetUv), ToVector(p.MeasuredMm)))
                .ToArray();
            calibration = new WallCalibration(serial, new Homography(c.LidarToUv), points, c.CentreErrorMm,
                DateTime.SpecifyKind(c.CalibratedAtUtc, DateTimeKind.Utc));
        }

        return new LidarConfigEntry
        {
            Calibration = calibration,
            AngleOffsetDeg = dto.AngleOffsetDeg,
            Mirror = dto.Mirror,
            TargetScreen = dto.TargetScreen,
        };
    }

    private static Vector2 ToVector(float[]? xy) => xy is { Length: 2 } ? new Vector2(xy[0], xy[1]) : Vector2.Zero;

    private sealed class FileDto
    {
        public int Version { get; set; }
        public Dictionary<string, EntryDto>? Lidars { get; set; }
    }

    private sealed class EntryDto
    {
        public float AngleOffsetDeg { get; set; }
        public bool Mirror { get; set; }
        public int? TargetScreen { get; set; }
        public CalibrationDto? Calibration { get; set; }
    }

    private sealed class CalibrationDto
    {
        /// <summary>Lidar millimetres to UV, 3×3 row-major.</summary>
        public double[]? LidarToUv { get; set; }
        public PointDto[]? Points { get; set; }
        public float CentreErrorMm { get; set; }
        public DateTime CalibratedAtUtc { get; set; }
    }

    private sealed class PointDto
    {
        public float[]? TargetUv { get; set; }
        public float[]? MeasuredMm { get; set; }
    }
}
