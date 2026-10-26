using System;
using System.Collections.Generic;
using Godot;

namespace Zurd.Lidar;

/// <summary>
/// A 3×3 projective transform between two planes, such as lidar millimetres and projected-image UV.
/// It maps straight lines to straight lines, so one transform absorbs rotation, scale, mirroring
/// and projector keystone. Immutable.
/// </summary>
public sealed class Homography
{
    private readonly double[] _m;

    /// <param name="matrix">Nine values, row-major.</param>
    public Homography(IReadOnlyList<double> matrix)
    {
        if (matrix.Count != 9)
            throw new ArgumentException("A homography needs exactly 9 values.", nameof(matrix));

        _m = new double[9];
        for (int i = 0; i < 9; i++)
            _m[i] = matrix[i];
    }

    /// <summary>The nine values, row-major. A copy, safe to store.</summary>
    public double[] ToArray() => (double[])_m.Clone();

    /// <summary>
    /// Maps a point. Fails only for points on the transform's "horizon", which can't occur inside
    /// a sensible calibrated area.
    /// </summary>
    public bool TryMap(Vector2 p, out Vector2 result)
    {
        double x = p.X, y = p.Y;
        double w = _m[6] * x + _m[7] * y + _m[8];
        if (Math.Abs(w) < 1e-12)
        {
            result = default;
            return false;
        }

        result = new Vector2(
            (float)((_m[0] * x + _m[1] * y + _m[2]) / w),
            (float)((_m[3] * x + _m[4] * y + _m[5]) / w));
        return true;
    }

    public bool TryInvert(out Homography inverse)
    {
        double[] m = _m;
        double c00 = m[4] * m[8] - m[5] * m[7];
        double c01 = m[5] * m[6] - m[3] * m[8];
        double c02 = m[3] * m[7] - m[4] * m[6];
        double det = m[0] * c00 + m[1] * c01 + m[2] * c02;
        if (Math.Abs(det) < 1e-15)
        {
            inverse = null!;
            return false;
        }

        // Adjugate (transposed cofactors) over the determinant.
        var inv = new[]
        {
            c00, m[2] * m[7] - m[1] * m[8], m[1] * m[5] - m[2] * m[4],
            c01, m[0] * m[8] - m[2] * m[6], m[2] * m[3] - m[0] * m[5],
            c02, m[1] * m[6] - m[0] * m[7], m[0] * m[4] - m[1] * m[3],
        };
        for (int i = 0; i < 9; i++)
            inv[i] /= det;

        inverse = new Homography(Normalised(inv));
        return true;
    }

    /// <summary>
    /// Least-squares fit of the transform taking each <paramref name="from"/> point to the matching
    /// <paramref name="to"/> point. Four pairs fit exactly; more are averaged. Uses the normalised
    /// direct linear transform: both point sets are first centred and scaled to unit size, which
    /// keeps the maths well conditioned when one side is millimetres and the other is 0..1.
    /// </summary>
    public static bool TryFit(IReadOnlyList<Vector2> from, IReadOnlyList<Vector2> to, out Homography homography)
    {
        homography = null!;
        int n = from.Count;
        if (n < 4 || to.Count != n)
            return false;

        double[] tFrom = NormalisingTransform(from);
        double[] tTo = NormalisingTransform(to);

        // Each pair gives two rows of A·h = b, with h = the first 8 entries and the last fixed at 1.
        // Solve the normal equations (AᵀA)·h = Aᵀb.
        var ata = new double[8, 8];
        var atb = new double[8];
        var row = new double[8];

        for (int i = 0; i < n; i++)
        {
            (double x, double y) = Apply(tFrom, from[i]);
            (double u, double v) = Apply(tTo, to[i]);

            Fill(row, x, y, 1, 0, 0, 0, -x * u, -y * u);
            Accumulate(ata, atb, row, u);
            Fill(row, 0, 0, 0, x, y, 1, -x * v, -y * v);
            Accumulate(ata, atb, row, v);
        }

        if (!TrySolve(ata, atb, out double[] h))
            return false;

        double[] normalised = { h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7], 1.0 };

        // Undo the normalisation: H = T_to⁻¹ · H_normalised · T_from.
        double[] tToInverse = InvertSimilarity(tTo);
        double[] result = Multiply(tToInverse, Multiply(normalised, tFrom));
        homography = new Homography(Normalised(result));
        return true;
    }

    // ------------------------------------------------------------------ helpers

    /// <summary>Scales so the last entry is 1, when it can be, so stored values are easy to read.</summary>
    private static double[] Normalised(double[] m)
    {
        if (Math.Abs(m[8]) < 1e-12)
            return m;

        double s = m[8];
        for (int i = 0; i < 9; i++)
            m[i] /= s;
        return m;
    }

    /// <summary>Similarity transform moving the points' centroid to the origin and their mean distance to √2.</summary>
    private static double[] NormalisingTransform(IReadOnlyList<Vector2> points)
    {
        double cx = 0, cy = 0;
        foreach (Vector2 p in points)
        {
            cx += p.X;
            cy += p.Y;
        }

        cx /= points.Count;
        cy /= points.Count;

        double meanDistance = 0;
        foreach (Vector2 p in points)
            meanDistance += Math.Sqrt((p.X - cx) * (p.X - cx) + (p.Y - cy) * (p.Y - cy));
        meanDistance /= points.Count;

        double s = meanDistance > 1e-12 ? Math.Sqrt(2) / meanDistance : 1.0;
        return new[] { s, 0, -s * cx, 0, s, -s * cy, 0, 0, 1 };
    }

    private static double[] InvertSimilarity(double[] t)
    {
        double s = t[0];
        return new[] { 1 / s, 0, -t[2] / s, 0, 1 / s, -t[5] / s, 0, 0, 1 };
    }

    private static (double X, double Y) Apply(double[] t, Vector2 p) =>
        (t[0] * p.X + t[1] * p.Y + t[2], t[3] * p.X + t[4] * p.Y + t[5]);

    private static double[] Multiply(double[] a, double[] b)
    {
        var r = new double[9];
        for (int i = 0; i < 3; i++)
        for (int j = 0; j < 3; j++)
            r[i * 3 + j] = a[i * 3] * b[j] + a[i * 3 + 1] * b[3 + j] + a[i * 3 + 2] * b[6 + j];
        return r;
    }

    private static void Fill(double[] row, params double[] values) => Array.Copy(values, row, values.Length);

    private static void Accumulate(double[,] ata, double[] atb, double[] row, double rhs)
    {
        for (int i = 0; i < 8; i++)
        {
            atb[i] += row[i] * rhs;
            for (int j = 0; j < 8; j++)
                ata[i, j] += row[i] * row[j];
        }
    }

    /// <summary>Gaussian elimination with partial pivoting. Fails if the system is (nearly) singular.</summary>
    private static bool TrySolve(double[,] a, double[] b, out double[] x)
    {
        int n = b.Length;
        x = new double[n];

        for (int col = 0; col < n; col++)
        {
            int pivot = col;
            for (int r = col + 1; r < n; r++)
            {
                if (Math.Abs(a[r, col]) > Math.Abs(a[pivot, col]))
                    pivot = r;
            }

            if (Math.Abs(a[pivot, col]) < 1e-10)
                return false;

            if (pivot != col)
            {
                for (int c = 0; c < n; c++)
                    (a[col, c], a[pivot, c]) = (a[pivot, c], a[col, c]);
                (b[col], b[pivot]) = (b[pivot], b[col]);
            }

            for (int r = col + 1; r < n; r++)
            {
                double f = a[r, col] / a[col, col];
                for (int c = col; c < n; c++)
                    a[r, c] -= f * a[col, c];
                b[r] -= f * b[col];
            }
        }

        for (int r = n - 1; r >= 0; r--)
        {
            double sum = b[r];
            for (int c = r + 1; c < n; c++)
                sum -= a[r, c] * x[c];
            x[r] = sum / a[r, r];
        }

        return true;
    }
}
