using System.Collections.Generic;
using Godot;

namespace Zurd.Lidar;

/// <summary>
/// Follows touch-sized blobs from one rotation to the next so each touch keeps its id. A blob must
/// appear for a few rotations in a row before it counts (one-rotation blips are noise), and a
/// touch survives a short dropout before it ends.
/// Not thread-safe; owned by <see cref="TouchDetector"/>.
/// </summary>
internal sealed class TouchTracker
{
    private readonly List<Track> _tracks = new();
    private readonly List<(float Distance, int Track, int Blob)> _pairs = new();
    private int _nextId = 1;

    /// <summary>Drops every track without reporting it as ended. Ids keep counting up.</summary>
    public void Reset() => _tracks.Clear();

    public void Update(
        IReadOnlyList<TouchBlob> blobs,
        double nowSec,
        TouchDetectorOptions opt,
        List<TrackedTouch> touches,
        List<TouchEvent> events)
    {
        // Pair tracks with blobs nearest-first, so two touches passing close by keep their own ids.
        _pairs.Clear();
        for (int t = 0; t < _tracks.Count; t++)
        {
            for (int b = 0; b < blobs.Count; b++)
            {
                if (!blobs[b].IsTouchSized)
                    continue;

                float distance = _tracks[t].Position.DistanceTo(blobs[b].CentroidMm);
                if (distance <= opt.MatchRadiusMm)
                    _pairs.Add((distance, t, b));
            }
        }

        _pairs.Sort((x, y) => x.Distance.CompareTo(y.Distance));

        var trackMatched = new bool[_tracks.Count];
        var blobMatched = new bool[blobs.Count];
        foreach (var (_, t, b) in _pairs)
        {
            if (trackMatched[t] || blobMatched[b])
                continue;

            trackMatched[t] = true;
            blobMatched[b] = true;

            Track track = _tracks[t];
            track.Position = blobs[b].CentroidMm;
            track.WidthMm = blobs[b].WidthMm;
            track.LastSeenSec = nowSec;
            track.SeenRotations++;
            track.MissedRotations = 0;
        }

        // A candidate that skips a rotation was noise. A confirmed touch gets a grace period.
        for (int t = _tracks.Count - 1; t >= 0; t--)
        {
            if (trackMatched[t])
                continue;

            Track track = _tracks[t];
            track.MissedRotations++;

            if (!track.Confirmed)
            {
                _tracks.RemoveAt(t);
            }
            else if (track.MissedRotations >= opt.ReleaseRotations)
            {
                events.Add(new TouchEvent(TouchEventKind.Ended, track.Id, track.Position, nowSec,
                    track.LastSeenSec - track.StartedSec));
                _tracks.RemoveAt(t);
            }
        }

        for (int b = 0; b < blobs.Count; b++)
        {
            if (blobMatched[b] || !blobs[b].IsTouchSized)
                continue;

            _tracks.Add(new Track
            {
                Position = blobs[b].CentroidMm,
                WidthMm = blobs[b].WidthMm,
                StartedSec = nowSec,
                LastSeenSec = nowSec,
                SeenRotations = 1,
            });
        }

        foreach (Track track in _tracks)
        {
            if (!track.Confirmed && track.SeenRotations >= opt.ConfirmRotations)
            {
                // Ids are handed out on confirmation, so the ones you see have no gaps from noise.
                track.Confirmed = true;
                track.Id = _nextId++;
                events.Add(new TouchEvent(TouchEventKind.Began, track.Id, track.Position, nowSec,
                    nowSec - track.StartedSec));
            }

            touches.Add(new TrackedTouch(track.Id, track.Confirmed, track.Position, track.WidthMm,
                track.StartedSec, track.MissedRotations));
        }
    }

    private sealed class Track
    {
        public int Id;
        public bool Confirmed;
        public Vector2 Position;
        public float WidthMm;
        public double StartedSec;
        public double LastSeenSec;
        public int SeenRotations;
        public int MissedRotations;
    }
}
