const std = @import("std");
const DateTime = @This();

timestamp_secs: u64,
year: u16,
month: u4,
day: u5,
hours: u5,
mins: u6,
secs: u6,

pub fn getUTC() DateTime {
    const timestamp_secs_i = @max(std.time.timestamp(), 0);
    const timestamp_secs: u64 = @intCast(timestamp_secs_i);
    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = timestamp_secs };
    const year_day = epoch_seconds.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = epoch_seconds.getDaySeconds();
    const hours = day_seconds.getHoursIntoDay();
    const mins = day_seconds.getMinutesIntoHour();
    const secs = day_seconds.getSecondsIntoMinute();
    return .{
        .timestamp_secs = timestamp_secs,
        .year = year_day.year,
        .month = month_day.month.numeric(),
        .day = month_day.day_index + 1,
        .hours = hours,
        .mins = mins,
        .secs = secs,
    };
}

pub fn format(self: DateTime, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) error{FormatFail}!void {
    _ = fmt;
    _ = options;
    writer.print("{:0>4}-{:0>2}-{:0>2}T{:0>2}:{:0>2}:{:0>2}Z", .{ self.year, self.month, self.day, self.hours, self.mins, self.secs }) catch return error{FormatFail}.FormatFail;
}
