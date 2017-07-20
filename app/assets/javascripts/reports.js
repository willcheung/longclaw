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