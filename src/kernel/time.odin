package kernel



Date_Time :: struct {
    year: u16,
    month, day, hour, minute, second: u8,
    nanosecond: u32,
    time_zone: i16,
    daylight: u8
}

#assert(size_of(Date_Time) == 16)

get_day_of_week :: proc(y, m, d: u64) -> string {
    days := []string {
        "",
        "Monday",
        "Tuesday",
        "Wednesday",
        "Thursday",
        "Friday",
        "Saturday",
        "Saturday"
    }

    m := m
    y := y

    //January and February are counted as months 13 and 14 of the previous year
    if m <= 2 {
       m += 12;
       y -= 1;
    }

    //J is the century
    j := y / 100;
    //K the year of the century
    k := y % 100;
  
    //Compute H using Zeller's congruence
    h := d + (26 * (m + 1) / 10) + k + (k / 4) + (5 * j) + (j / 4);
  
    //Return the day of the week
    index := ((h + 5) % 7) + 1;

    return days[index];
}

unix_time_to_date_time :: proc(t: u64) -> Date_Time {
    t := t
    
    result: Date_Time

    result.nanosecond = 0

    result.second = u8(t % 60)
    t /= 60
    result.minute = u8(t % 60)
    t /= 60
    result.hour = u8(t % 24)
    t /= 24

    //Convert Unix time to date
    a := ((4 * t + 102032) / 146097 + 15)
    b := (t + 2442113 + a - (a / 4))
    c := (20 * b - 2442) / 7305
    d := b - 365 * c - (c / 4)
    e := d * 1000 / 30601
    f := d - e * 30 - e * 601 / 1000

    //January and February are counted as months 13 and 14 of the previous year
    if e <= 13 {
       c -= 4716
       e -= 1
    } else {
       c -= 4715
       e -= 13
    }

    //Retrieve year, month and day
    result.year = u16(c);
    result.month = u8(e);
    result.day = u8(f);
  
    return result
}