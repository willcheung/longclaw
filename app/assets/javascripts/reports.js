// Place all the behaviors and hooks related to the matching controller here.
// All this logic will automatically be available in application.js.

//= require daterangepicker/moment.min.js
//= require daterangepicker/daterangepicker.js

/* Tooltip */
$('[data-toggle="tooltip"]').tooltip();

/* Chosen */
$('.metric_filter').chosen({ disable_search: true, allow_single_deselect: true}); 
$('.category_filter').chosen({ disable_search: true, allow_single_deselect: true});

$('input[name="daterange"]').daterangepicker({
    "alwaysShowCalendars": true,
    "opens": "left",
    "startDate": moment().subtract(1, 'year').startOf('year'), 
    "endDate": moment().subtract(1, 'year').endOf('year'),
    "ranges": {
        "Last 30 Days": [
            moment().subtract(30, "days").format("l"),
            moment().format("l")
        ],
        "Last 180 days": [
            moment().subtract(180, "days").format("l"),
            moment().format("l")
        ],
        "Year 2016": [
            moment().subtract(1, 'year').startOf('year'), 
            moment().subtract(1, 'year').endOf('year')
        ],
        "Year 2015": [
            moment().subtract(2, 'year').startOf('year'), 
            moment().subtract(2, 'year').endOf('year')
        ]
    }
});

/*
    Converts a number into human readable string.
    Note: Returns undefined for numbers larger than 999 septillion or smaller than 999 septillionth
    Number names refs: http://wiki.answers.com/Q/What_number_is_after_vigintillion&src=ansTT
                       https://en.wikipedia.org/wiki/Names_of_large_numbers
*/
function large_number_to_human(number) {
    if (number == 0) return 0;
    if (!number || Math.abs(number) > 100000000000000000000000000) return; // 10^24
    var sign = (number < 0) ? "-" : "";
    number = Math.abs(number);
    var s = ['','K', 'M', 'B', 'T', 'Quad', 'Quint', 'Sext', 'Sept']; 
    var e = Math.floor(Math.log(number) / Math.log(1000));
    var precision = (e > 0) ? 1 : 0;
    return sign + ((number / Math.pow(1000, e)).toFixed(precision) + "" + s[e]);
}

/*
  Formats seconds into days hh:mm format
  e.g., convert_secs_to_ddhhmm(59)       => "00:00"
        convert_secs_to_ddhhmm(60)       => "00:01"
        convert_secs_to_ddhhmm(61)       => "00:01"
        convert_secs_to_ddhhmm(3599);    => "00:59"
        convert_secs_to_ddhhmm(3600);    => "01:00"
        convert_secs_to_ddhhmm(86399);   => "23:59"
        convert_secs_to_ddhhmm(86400);   => "1d 00:00"
        convert_secs_to_ddhhmm(1209599); => "13d 23:59"
        convert_secs_to_ddhhmm(1209600); => "14d 00:00"
*/
function convert_secs_to_ddhhmm(secs) {
    var prefix = "";
    var t = new Date(1970, 0, 1); // Epoch
    t.setSeconds(secs);

    var hhmmss = t.toString().substring(16,24);
    var d = Math.floor(secs / 86400);

    var hh = hhmmss.substring(0,2);
    var mm = hhmmss.substring(3,5);
    //var ss = hhmmss.substring(6,8);
    if (d > 0) 
        prefix = d + "d ";
    return prefix + hh + ":" + mm /*+":"+ss*/;
}
