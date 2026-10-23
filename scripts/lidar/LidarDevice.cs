using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Diagnostics.CodeAnalysis;
using System.IO.Ports;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using RpLidar.NET;
using RpLidar.NET.Entities;

namespace Zurd.Lidar;

/// <summary>
/// One RPLidar A-series sensor on one serial port. Wraps <see cref="RpLidarSerialDevice"/> so the
/// rest of the game gets whole rotations (<see cref="LidarScan"/>) and an honest status report
/// instead of raw driver events.
/// <para>
/// Plain C#, no Godot nodes: create one per sensor, call <see cref="ConnectAsync"/>, then poll
/// <see cref="TryGetNewScan"/> and <see cref="GetStatus"/> from the main thread (or subscribe to
/// <see cref="ScanReceived"/>, which fires on the driver's scan thread).
/// </para>
/// <para>
/// Why this wrapper does not call the driver's own <c>Start()</c>: with a bad or busy port that
/// method retries forever without sleeping, which would freeze whichever thread called it. This
/// class runs the same steps once, on a worker thread, and reports what went wrong.
/// </para>
/// </summary>
public sealed class LidarDevice : IDisposable
{
    private const double PointWindowSec = 1.5;
    private const double RevWindowSec = 2.0;
    private const int RevWindowMax = 8;

    private readonly object _lifecycleLock = new();
    private readonly object _statsLock = new();

    private RpLidarSerialDevice? _device;
    private LidarSettings? _settings;
    private volatile RevolutionAssembler? _assembler;
    private bool _disposed;

    private volatile LidarConnectionState _state = LidarConnectionState.Disconnected;
    private volatile string? _error;
    private volatile LidarDeviceInfo? _info;
    private volatile LidarScan? _latest;

    private long _sequence;
    private long _totalPoints;
    private long _totalRevolutions;
    private long _lastDataTimestamp;
    private long _streamStartTimestamp;
    private readonly Queue<(long Ts, int Points)> _pointWindow = new();
    private readonly Queue<(long Ts, int Count)> _revWindow = new();

    public LidarDevice(LidarDeviceOptions options)
    {
        Options = options;
    }

    public LidarDeviceOptions Options { get; }

    public LidarConnectionState State => _state;

    /// <summary>Why the last connect attempt failed, or null.</summary>
    public string? LastError => _error;

    /// <summary>Model, firmware and so on, available while streaming.</summary>
    public LidarDeviceInfo? Info => _info;

    /// <summary>The most recent complete rotation, or null if none has arrived since connecting.</summary>
    public LidarScan? LatestScan => _latest;

    /// <summary>
    /// Raised once per completed rotation, on the driver's scan thread (not the Godot main
    /// thread). Keep handlers short and never call <see cref="DisconnectAsync"/> or
    /// <see cref="Dispose"/> from inside one.
    /// </summary>
    public event Action<LidarScan>? ScanReceived;

    // ------------------------------------------------------------------ public API

    /// <summary>Serial ports the OS currently reports, shortest name first (COM3 before COM10).</summary>
    public static string[] ListPorts()
    {
        try
        {
            return SerialPort.GetPortNames()
                .OrderBy(p => p.Length)
                .ThenBy(p => p, StringComparer.OrdinalIgnoreCase)
                .ToArray();
        }
        catch (Exception)
        {
            return Array.Empty<string>();
        }
    }

    /// <summary>
    /// Opens the port, asks the lidar who it is, spins up the motor and starts scanning. Takes a
    /// few seconds, so it runs on a worker thread. Never throws: check <see cref="State"/> and
    /// <see cref="LastError"/> afterwards (or just watch <see cref="GetStatus"/>).
    /// </summary>
    public Task ConnectAsync()
    {
        if (_disposed)
            return Task.CompletedTask;

        // Flip the state now, not when the worker gets scheduled, so a UI polling State never
        // sees "Disconnected" right after the user pressed Connect.
        _state = LidarConnectionState.Connecting;
        return Task.Run(Connect);
    }

    /// <summary>Stops the scan and motor and closes the port. Takes about a second.</summary>
    public Task DisconnectAsync()
    {
        if (_disposed)
            return Task.CompletedTask;

        _state = LidarConnectionState.Stopping;
        return Task.Run(Disconnect);
    }

    /// <summary>Changes motor speed (0..1023). Applied immediately if streaming, otherwise on next connect.</summary>
    public Task SetMotorPwmAsync(ushort pwm) => Task.Run(() => SetMotorPwm(pwm));

    /// <summary>
    /// Returns the latest rotation if it is newer than <paramref name="lastSequence"/>.
    /// Cheap and lock-free; call it every frame.
    /// </summary>
    public bool TryGetNewScan(long lastSequence, [NotNullWhen(true)] out LidarScan? scan)
    {
        LidarScan? latest = _latest;
        if (latest is not null && latest.Sequence != lastSequence)
        {
            scan = latest;
            return true;
        }

        scan = null;
        return false;
    }

    /// <summary>Builds the three-stage status. Cheap; safe to call from any thread.</summary>
    public LidarStatus GetStatus()
    {
        LidarConnectionState state = _state;
        LidarDeviceInfo? info = _info;
        string? error = _error;
        LidarDeviceOptions opt = Options;

        double freq = Stopwatch.Frequency;
        long now = Stopwatch.GetTimestamp();
        long lastData = Volatile.Read(ref _lastDataTimestamp);
        long streamStart = Volatile.Read(ref _streamStartTimestamp);
        double sinceLast = lastData == 0 ? double.PositiveInfinity : (now - lastData) / freq;
        double sinceStart = streamStart == 0 ? 0.0 : (now - streamStart) / freq;

        float pointsPerSecond = 0f;
        float revHz = 0f;
        float pointsPerRev = 0f;

        lock (_statsLock)
        {
            TrimWindows(now);

            long pointsInWindow = 0;
            foreach (var entry in _pointWindow)
                pointsInWindow += entry.Points;

            double window = Math.Min(PointWindowSec, sinceStart);
            if (window > 0.25)
                pointsPerSecond = (float)(pointsInWindow / window);

            int revCount = _revWindow.Count;
            if (revCount >= 1)
            {
                long firstTs = _revWindow.Peek().Ts;
                long lastTs = firstTs;
                long pointSum = 0;
                foreach (var rev in _revWindow)
                {
                    lastTs = rev.Ts;
                    pointSum += rev.Count;
                }

                pointsPerRev = pointSum / (float)revCount;

                double span = (lastTs - firstTs) / freq;
                if (revCount >= 2 && span > 0.0)
                    revHz = (float)((revCount - 1) / span);
            }
        }

        LidarStage connection = state switch
        {
            LidarConnectionState.Disconnected => new(LidarStageState.Pending, "Not connected."),
            LidarConnectionState.Connecting => new(LidarStageState.Pending, $"Opening {opt.Port}…"),
            LidarConnectionState.Stopping => new(LidarStageState.Pending, "Stopping…"),
            LidarConnectionState.Failed => new(LidarStageState.Failed, error ?? "Connection failed."),
            _ => new(LidarStageState.Ok, info is null
                ? opt.Port
                : $"{opt.Port} · {info.ModelName} · firmware {info.Firmware}"),
        };

        LidarStage data = EvaluateData(state, opt, sinceStart, sinceLast, pointsPerSecond, revHz);
        LidarStage health = EvaluateHealth(data, opt, info, Interlocked.Read(ref _totalRevolutions), revHz, pointsPerRev);

        return new LidarStatus
        {
            State = state,
            Connection = connection,
            Data = data,
            Health = health,
            PointsPerSecond = pointsPerSecond,
            RevolutionsPerSecond = revHz,
            PointsPerRevolution = pointsPerRev,
            SecondsSinceLastData = sinceLast,
            TotalPoints = Interlocked.Read(ref _totalPoints),
            TotalRevolutions = Interlocked.Read(ref _totalRevolutions),
            Device = info,
        };
    }

    /// <summary>Stops everything and releases the port. Blocks briefly; call it when the node leaves the tree.</summary>
    public void Dispose()
    {
        lock (_lifecycleLock)
        {
            if (_disposed)
                return;

            _disposed = true;
            TeardownLocked();
            _state = LidarConnectionState.Disconnected;
        }
    }

    // ------------------------------------------------------------------ lifecycle (worker thread)

    private void Connect()
    {
        lock (_lifecycleLock)
        {
            if (_disposed)
                return;

            TeardownLocked();
            ResetStats();
            _error = null;
            _info = null;
            _state = LidarConnectionState.Connecting;

            try
            {
                PreflightPort();

                var settings = new LidarSettings
                {
                    Port = Options.Port,
                    BaudRate = Options.BaudRate,
                    ScanMode = Options.ScanMode,
                    Pwm = Options.MotorPwm,
                    MaxDistance = Options.MaxDistanceMm,
                    ElapsedMilliseconds = Options.BatchIntervalMs,
                };

                var device = new RpLidarSerialDevice(settings);
                _settings = settings;
                _device = device;

                // The driver swallows open failures and only prints them, so success is proven by
                // the lidar answering a request, not by this call returning.
                device.Connect();
                _info = QueryDeviceInfo(device);

                _assembler = new RevolutionAssembler(OnRevolution);
                device.LidarPointScanEvent += OnBatch;

                // Same steps as the driver's own Start(), minus its endless retry loop.
                device.StopScan();
                if (settings.ScanMode == ScanMode.Standard)
                    device.StartScan();
                else
                    device.ForceScanExpress();

                Volatile.Write(ref _streamStartTimestamp, Stopwatch.GetTimestamp());
                _state = LidarConnectionState.Streaming;
            }
            catch (Exception e)
            {
                _error = e is LidarConnectException ? e.Message : $"{e.GetType().Name}: {e.Message}";
                TeardownLocked();
                _state = LidarConnectionState.Failed;
            }
        }
    }

    private void Disconnect()
    {
        lock (_lifecycleLock)
        {
            if (_disposed)
                return;

            _state = LidarConnectionState.Stopping;
            TeardownLocked();
            _error = null;
            _info = null;
            _state = LidarConnectionState.Disconnected;
        }
    }

    private void SetMotorPwm(ushort pwm)
    {
        if (pwm > 1023)
            pwm = 1023;

        Options.MotorPwm = pwm;

        lock (_lifecycleLock)
        {
            if (_disposed || _device is null || _settings is null || _state != LidarConnectionState.Streaming)
                return;

            try
            {
                _settings.Pwm = pwm;
                _device.StartMotor();
            }
            catch (Exception)
            {
                // A failed speed change is not worth tearing the connection down; the status
                // panel will show it if the rotation rate goes wrong.
            }
        }
    }

    /// <summary>Stops the scan, motor and port, in the order the driver needs. Caller holds the lifecycle lock.</summary>
    private void TeardownLocked()
    {
        RpLidarSerialDevice? device = _device;
        _device = null;
        _settings = null;
        _assembler = null;

        if (device is not null)
        {
            device.LidarPointScanEvent -= OnBatch;

            // Stop first (halts the read thread and motor), then close, then dispose. Calling
            // Dispose alone would run the slow stop-motor sequence a second time.
            try { device.Stop(); } catch (Exception) { }
            try { device.Disconnect(); } catch (Exception) { }
            try { device.Dispose(); } catch (Exception) { }
        }

        // Only now is the read thread guaranteed finished, so nothing can republish a scan.
        _latest = null;
    }

    private void ResetStats()
    {
        lock (_statsLock)
        {
            _pointWindow.Clear();
            _revWindow.Clear();
        }

        Interlocked.Exchange(ref _totalPoints, 0);
        Interlocked.Exchange(ref _totalRevolutions, 0);
        Volatile.Write(ref _lastDataTimestamp, 0);
        Volatile.Write(ref _streamStartTimestamp, 0);
    }

    // ------------------------------------------------------------------ connect helpers

    private void PreflightPort()
    {
        string port = Options.Port;
        if (string.IsNullOrWhiteSpace(port))
            throw new LidarConnectException("No serial port selected.");

        string[] available = ListPorts();
        if (!available.Contains(port, StringComparer.OrdinalIgnoreCase))
        {
            throw new LidarConnectException(available.Length == 0
                ? $"{port} not found, and the OS reports no serial ports. Is the lidar's USB cable plugged in?"
                : $"{port} not found. Available ports: {string.Join(", ", available)}.");
        }

        // Open and close once ourselves so the failure reason (usually "already in use") reaches
        // the user instead of vanishing into the driver's console output.
        try
        {
            using var probe = new SerialPort(port, Options.BaudRate);
            probe.Open();
        }
        catch (UnauthorizedAccessException e)
        {
            throw new LidarConnectException(
                $"Access to {port} was denied. Another program probably has it open (RoboStudio, a serial " +
                "monitor, another copy of the game). On Linux you may need to join the 'dialout' group.", e);
        }
        catch (Exception e)
        {
            throw new LidarConnectException($"Could not open {port}: {e.Message}", e);
        }

        // Give the OS a moment to release the port before the driver opens it.
        Thread.Sleep(150);
    }

    private LidarDeviceInfo QueryDeviceInfo(RpLidarSerialDevice device)
    {
        // The lidar can take a moment to wake after the port opens, so retry a few times.
        InfoDataResponse? info = null;
        Exception? lastFailure = null;
        for (int attempt = 0; attempt < 3 && info is null; attempt++)
        {
            try
            {
                info = device.SendRequest(Command.GetInfo) as InfoDataResponse;
            }
            catch (Exception e)
            {
                lastFailure = e;
            }

            if (info is null)
                Thread.Sleep(250);
        }

        if (info is null)
        {
            string detail = lastFailure is null ? "" : $" ({lastFailure.Message})";
            throw new LidarConnectException(
                $"The lidar on {Options.Port} did not answer a GetInfo request{detail}. Check that it is " +
                $"powered, that {Options.BaudRate} baud is right for this model, and that this is its port.",
                lastFailure);
        }

        int healthStatus = -1;
        int healthCode = 0;
        try
        {
            if (device.SendRequest(Command.GetHealth) is RpHealthResponse health)
            {
                healthStatus = health.Status;
                healthCode = health.ErrorCode;
            }
        }
        catch (Exception)
        {
            // Health is a bonus; the stage simply reports it as unknown.
        }

        return new LidarDeviceInfo(
            DescribeModel(info.ModelId),
            info.FirmwareVersion ?? "?",
            info.HardwareVersion ?? "?",
            info.SerialNumber ?? "",
            healthStatus,
            healthCode);
    }

    private static string DescribeModel(string? modelId)
    {
        if (byte.TryParse(modelId, out byte id))
        {
            switch (id)
            {
                case 0x18: return "A1M8";
                case 0x28: return "A2M8";
                default: return $"model 0x{id:X2}";
            }
        }

        return "unknown model";
    }

    // ------------------------------------------------------------------ data path (driver scan thread)

    private void OnBatch(List<LidarPoint> batch)
    {
        RevolutionAssembler? assembler = _assembler;
        if (assembler is null || batch.Count == 0)
            return;

        try
        {
            long now = Stopwatch.GetTimestamp();
            Volatile.Write(ref _lastDataTimestamp, now);
            Interlocked.Add(ref _totalPoints, batch.Count);

            lock (_statsLock)
            {
                _pointWindow.Enqueue((now, batch.Count));
                TrimWindows(now);
            }

            assembler.Add(batch);
        }
        catch (Exception)
        {
            // Never let a bug here escape into the driver's read loop.
        }
    }

    private void OnRevolution(LidarSample[] samples)
    {
        long now = Stopwatch.GetTimestamp();
        long sequence = Interlocked.Increment(ref _sequence);
        Interlocked.Increment(ref _totalRevolutions);

        lock (_statsLock)
        {
            _revWindow.Enqueue((now, samples.Length));
            while (_revWindow.Count > RevWindowMax)
                _revWindow.Dequeue();
        }

        var scan = new LidarScan(sequence, now / (double)Stopwatch.Frequency, samples);
        _latest = scan;

        try
        {
            ScanReceived?.Invoke(scan);
        }
        catch (Exception)
        {
            // A subscriber's bug must not stop the scan.
        }
    }

    /// <summary>Drops stats entries that have aged out. Caller holds the stats lock.</summary>
    private void TrimWindows(long now)
    {
        double freq = Stopwatch.Frequency;

        long pointCutoff = now - (long)(PointWindowSec * freq);
        while (_pointWindow.Count > 0 && _pointWindow.Peek().Ts < pointCutoff)
            _pointWindow.Dequeue();

        long revCutoff = now - (long)(RevWindowSec * freq);
        while (_revWindow.Count > 0 && _revWindow.Peek().Ts < revCutoff)
            _revWindow.Dequeue();
    }

    // ------------------------------------------------------------------ status stages

    private static LidarStage EvaluateData(
        LidarConnectionState state,
        LidarDeviceOptions opt,
        double sinceStart,
        double sinceLast,
        float pointsPerSecond,
        float revHz)
    {
        if (state != LidarConnectionState.Streaming)
            return new LidarStage(LidarStageState.Pending, "—");

        if (double.IsPositiveInfinity(sinceLast))
        {
            return sinceStart < opt.NoDataTimeoutSec
                ? new LidarStage(LidarStageState.Pending, $"Waiting for data… {sinceStart:F0} s")
                : new LidarStage(LidarStageState.Failed,
                    $"No data after {sinceStart:F0} s. Is the motor spinning? Try another scan mode.");
        }

        if (sinceLast > opt.StallTimeoutSec)
        {
            return new LidarStage(LidarStageState.Failed,
                $"Data stopped {sinceLast:F1} s ago. Cable unplugged? Press Disconnect, then Connect.");
        }

        return new LidarStage(LidarStageState.Ok, $"{pointsPerSecond:F0} points/s · {revHz:F1} rotations/s");
    }

    private static LidarStage EvaluateHealth(
        LidarStage data,
        LidarDeviceOptions opt,
        LidarDeviceInfo? info,
        long totalRevolutions,
        float revHz,
        float pointsPerRev)
    {
        if (data.State != LidarStageState.Ok)
            return new LidarStage(LidarStageState.Pending, "—");

        if (totalRevolutions < 3 || revHz <= 0f)
            return new LidarStage(LidarStageState.Pending, "Measuring…");

        if (info is { HealthStatus: 2 })
        {
            return new LidarStage(LidarStageState.Failed,
                $"The lidar reports an error (code 0x{info.HealthErrorCode:X}). Power-cycle it.");
        }

        if (revHz < opt.MinRevolutionHz)
        {
            return new LidarStage(LidarStageState.Warning,
                $"Rotating at {revHz:F1} Hz, expected {opt.MinRevolutionHz:F0}–{opt.MaxRevolutionHz:F0}. Motor slow: raise the motor speed.");
        }

        if (revHz > opt.MaxRevolutionHz)
        {
            return new LidarStage(LidarStageState.Warning,
                $"Rotating at {revHz:F1} Hz, expected {opt.MinRevolutionHz:F0}–{opt.MaxRevolutionHz:F0}. Lower the motor speed.");
        }

        if (pointsPerRev < opt.MinPointsPerRevolution)
        {
            return new LidarStage(LidarStageState.Warning,
                $"Only {pointsPerRev:F0} points per rotation, expected at least {opt.MinPointsPerRevolution}. Dirty window, or most targets out of range?");
        }

        if (info is { HealthStatus: 1 })
        {
            return new LidarStage(LidarStageState.Warning,
                $"The lidar reports a warning (code 0x{info.HealthErrorCode:X}), but the data looks fine.");
        }

        string healthNote = info is { HealthStatus: 0 } ? " · lidar reports healthy" : "";
        return new LidarStage(LidarStageState.Ok, $"{revHz:F1} Hz · {pointsPerRev:F0} points/rotation{healthNote}");
    }

    /// <summary>A connect failure whose message is already written for the user.</summary>
    private sealed class LidarConnectException : Exception
    {
        public LidarConnectException(string message, Exception? inner = null) : base(message, inner)
        {
        }
    }
}
