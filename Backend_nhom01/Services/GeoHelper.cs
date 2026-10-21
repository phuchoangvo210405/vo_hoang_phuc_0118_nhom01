namespace vo_hoang_phuc_0118_nhom01.Services;

public static class GeoHelper
{
    private const double EarthRadiusM = 6371000;

    // Khoảng cách (mét) giữa hai toạ độ theo công thức Haversine.
    public static double DistanceMeters(double lat1, double lon1, double lat2, double lon2)
    {
        static double ToRad(double deg) => deg * Math.PI / 180;

        var dLat = ToRad(lat2 - lat1);
        var dLon = ToRad(lon2 - lon1);
        var a = Math.Sin(dLat / 2) * Math.Sin(dLat / 2) +
                Math.Cos(ToRad(lat1)) * Math.Cos(ToRad(lat2)) * Math.Sin(dLon / 2) * Math.Sin(dLon / 2);
        return EarthRadiusM * 2 * Math.Atan2(Math.Sqrt(a), Math.Sqrt(1 - a));
    }
}
