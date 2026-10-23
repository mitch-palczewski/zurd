namespace Zurd.Lidar;

/// <summary>
/// Settings for one <see cref="TouchDetector"/>. The baseline bin size and rotation count are read
/// when a capture starts; everything else is read every rotation, so it can be tuned live.
/// </summary>
public sealed class TouchDetectorOptions
{
    // ---- Baseline ----

    /// <summary>Rotations to record for a baseline. 20 is about 3.5 s on an A1.</summary>
    public int BaselineRotations { get; set; } = 20;

    /// <summary>
    /// Angular width of one baseline bin. An A1 in Sensitivity mode spaces its points about 0.25°
    /// apart, so each bin gets a couple of readings per rotation.
    /// </summary>
    public float BaselineBinDeg { get; set; } = 0.5f;

    /// <summary>
    /// Which of a bin's captured distances becomes its reference, from 0 (nearest) to 1 (farthest).
    /// Low, so an edge that flickers between near and far is remembered as near; not zero, so one
    /// stray reading cannot blind the bin.
    /// </summary>
    public float BaselinePercentile { get; set; } = 0.1f;

    /// <summary>
    /// A point is compared with the nearest reference this many bins either side, which absorbs the
    /// small angle jitter between rotations at depth edges.
    /// </summary>
    public int BaselineSpreadBins { get; set; } = 1;

    // ---- Change detection ----

    /// <summary>How much closer than the baseline a point must be to count, at minimum.</summary>
    public float MinDepthChangeMm { get; set; } = 50f;

    /// <summary>
    /// The same margin as a fraction of the baseline distance; the larger of the two wins. The
    /// lidar's error grows with range, so far surfaces need a wider margin.
    /// </summary>
    public float RelativeDepthChange { get; set; } = 0.03f;

    /// <summary>Closer readings are ignored. 150 mm is the A1's rated minimum range.</summary>
    public float MinRangeMm { get; set; } = 150f;

    /// <summary>Farther readings are ignored, so people walking past at the far end of the room don't count.</summary>
    public float MaxRangeMm { get; set; } = 6000f;

    // ---- Blobs ----

    /// <summary>Foreground points closer together than this belong to the same blob.</summary>
    public float ClusterGapMm { get; set; } = 60f;

    /// <summary>
    /// Fewer points than this is noise. At 4 m the A1's points are about 17 mm apart, so a
    /// fingertip may only get one or two.
    /// </summary>
    public int MinPointsPerBlob { get; set; } = 2;

    /// <summary>Wider blobs (a body, a chair) are not touches.</summary>
    public float MaxBlobWidthMm { get; set; } = 400f;

    // ---- Tracking ----

    /// <summary>
    /// How far a touch may move between rotations and still be the same touch. A hand moving at
    /// 1 m/s covers about 180 mm per A1 rotation.
    /// </summary>
    public float MatchRadiusMm { get; set; } = 250f;

    /// <summary>Rotations in a row a blob must appear before it counts as a touch. 1 reacts fastest; 2 ignores one-rotation blips.</summary>
    public int ConfirmRotations { get; set; } = 2;

    /// <summary>Rotations in a row a touch may go unseen before it ends, so one dropped rotation doesn't split a touch in two.</summary>
    public int ReleaseRotations { get; set; } = 2;
}
