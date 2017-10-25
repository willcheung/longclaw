// Place all the behaviors and hooks related to the matching controller here.
// All this logic will automatically be available in application.js.

//= require daterangepicker/moment.min.js
//= require daterangepicker/daterangepicker.js
//= require iCheck/icheck.min.js

// Checking/Unchecking Tasks
// iCheck initialized on ad_account_data.html.erb
$(document).on('ifChecked', 'input', function(event){
  $.ajax({url:'/notifications/'+$(this).attr('id')+'/update_is_complete'});
});


$(document).on('ifUnchecked', 'input', function(event){
  $.ajax({url:'/notifications/'+$(this).attr('id')+'/update_is_complete'});
});


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

function reset_labels_on_axis(axis) {
    axis.update({
        stackLabels: {
            enabled: true,
            formatter: function () {
                return this.total;
            }
        }
    });
};

function reset_subtitles_on_chart(chart) {
    chart.subtitle.update({
        text: ' ' 
    });
};

/*
    Converts a number (at least equal to 1) into a human readable string.
    Note: Returns 0 for fractional values (absolute values less than 1), and undefined for numbers larger than 999 septillion (10^24-1) or smaller than -999 septillion (-10^24+1).
    Number names refs: http://wiki.answers.com/Q/What_number_is_after_vigintillion&src=ansTT
                       https://en.wikipedia.org/wiki/Names_of_large_numbers

*/
function large_number_to_human(number) {
  if (number == 0 || Math.abs(number) < 1) return 0;
  if (!number || Math.abs(number) > 100000000000000000000000000) return; // 10^24
  var sign = (number < 0) ? "-" : "";
  number = Math.abs(number);
  var s = ['','K', 'M', 'B', 'T', 'Quad', 'Quint', 'Sext', 'Sept'];
  var e = Math.floor(Math.log(number) / Math.log(1000));
  var precision = (e > 0) ? 1 : 0;
  return sign + ((number / Math.pow(1000, e)).toFixed(precision) + "" + s[e]);
}

/*
    Similar to large_number_to_human except it keeps a certain number of significant digits and discards the rest (always rounds down)
    large_number_to_human_signif_digits(9);        // 9
    large_number_to_human_signif_digits(99);       // 99
    large_number_to_human_signif_digits(199.9);    // 199
    large_number_to_human_signif_digits(1099.9);   // 1.09K
    large_number_to_human_signif_digits(11190);    // 11.1K
    large_number_to_human_signif_digits(103900);   // 103K
    large_number_to_human_signif_digits(104000);   // 104K
    large_number_to_human_signif_digits(104900);   // 104K
    large_number_to_human_signif_digits(1014900);  // 1.01M
*/
function large_number_to_human_signif_digits(number, significant_digits) {
    if (!significant_digits)
        significant_digits = 3;
    if (significant_digits < 0)
        significant_digits = 1;

    if (number == 0 || Math.abs(number) < 1) return 0;
    if (!number || Math.abs(number) > 100000000000000000000000000) return; // 10^24

    var sign = (number < 0) ? "-" : "";
    number = Math.abs(number);
    var s = ['','K', 'M', 'B', 'T', 'Quad', 'Quint', 'Sext', 'Sept'];
    var e = Math.floor(Math.log(number) / Math.log(1000));
    number = truncPrecision(number, significant_digits);
    return sign + (number / Math.pow(1000, e) + "" + s[e]);
}
// currently truncates by transforming into a string, removing the decimal point, taking a substring, then putting the decimal point back in the right place
function truncPrecision(number, significant_digits) {
    var number_str = number + "";
    var decimal_pos = number_str.search("\\.");
    var number_str_transform = number_str.replace(".","");  // remove the decimal pt
    number_str_transform = number_str_transform.substring(0, significant_digits);  // truncate to significant_digits digits

    if (decimal_pos >= 0 && decimal_pos <= 3) {
        return Number(number_str_transform.substring(0,decimal_pos) + "." + number_str_transform.substring(decimal_pos,number_str_transform.length));
    } else {
        var factor_adjust = (decimal_pos >= 0 ? decimal_pos : number_str.length) - significant_digits;
        return number_str_transform * Math.pow(10, factor_adjust);
    }
}

/*
  Formats seconds into h:mm format
  e.g., convert_secs_to_hhmm(59)      => "0:00"
        convert_secs_to_hhmm(60)      => "0:01"
        convert_secs_to_hhmm(61)      => "0:01"
        convert_secs_to_hhmm(3599);   => "0:59"
        convert_secs_to_hhmm(3600);   => "1:00"
        convert_secs_to_hhmm(86399);  => "23:59"
        convert_secs_to_hhmm(86400);  => "24:00"
        convert_secs_to_hhmm(172800); => "48:00"
*/
function convert_secs_to_hhmm(secs) {
    var hours = Math.floor(secs / 3600);
    var mins = Math.floor((secs - hours*3600) / 60);
    return hours + ":" + ("00" + mins).slice(-2);
}
