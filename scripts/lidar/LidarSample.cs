namespace Zurd.Lidar;

/// <summary>
/// One lidar measurement, copied out of the RpLidar.NET <c>LidarPoint</c> so the rest of the
/// game never touches the driver's mutable types.
/// </summary>
/// <param name="AngleDeg">Heading in degrees, 0..360. Increases clockwise when viewed from above the sensor.</param>
/// <param name="DistanceMm">Distance from the sensor's rotating core, in millimetres (always &gt; 0).</param>
/// <param name="Quality">Driver-reported quality. In the express modes (Sensitivity/Boost), the only
/// ones the driver decodes, it fills in a constant, so this carries no information.</param>
public readonly record struct LidarSample(float AngleDeg, float DistanceMm, ushort Quality);
