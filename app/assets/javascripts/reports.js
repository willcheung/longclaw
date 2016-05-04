// Place all the behaviors and hooks related to the matching controller here.
// All this logic will automatically be available in application.js.

//= require daterangepicker/moment.min.js
//= require daterangepicker/daterangepicker.js

/* Tooltip */
$('[data-toggle="tooltip"]').tooltip();

$('input[name="daterange"]').daterangepicker({
    "alwaysShowCalendars": true,
    "opens": "left",
    "cancelClass": "btn-danger",
    "startDate": moment().subtract(7, "days").format("l"),
    "ranges": {
        "Today": [
            moment().format("l"),
            moment().format("l")
        ],
        "Last 7 Days": [
            moment().subtract(7, "days").format("l"),
            moment().format("l")
        ],
        "Last 14 Days": [
            moment().subtract(14, "days").format("l"),
            moment().format("l")
        ],
        "Last 30 Days": [
            moment().subtract(30, "days").format("l"),
            moment().format("l")
        ],
        "Last 90 Days": [
            moment().subtract(90, "days").format("l"),
            moment().format("l")
        ],
        "This Month": [
            moment().date(1).format("l"),
            moment().date(moment().daysInMonth()).format("l")
        ]
    }
});