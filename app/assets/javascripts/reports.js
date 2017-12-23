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
$('.category_filter').chosen({ disable_search: true, allow_single_deselect: true, search_contains: true });

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


// function resetStagesFilter() {
//     let stageSelection = $('#stage-chart').highcharts().getSelectedPoints();
//     for (var i=0; i < stageSelection.length; i++) {
//         stageSelection[i].select(false); // de-select
//     }
// };

// function setFilterParamsAndReloadPage() {
//   var params = {};
//   params.type = $('#type-filter').val() ? $('#type-filter').val() : "";
//   params.owner = $('#owner-filter').val() ? $('#owner-filter').val() : "";
//   params.close_date = $('#close-date-filter').val() ? $('#close-date-filter').val() : "Any";
//   params.stage = getSelection('#stage-chart');
//   params.forecast = getSelection('#forecast-chart');
//
//   window.location.search = $.param(params);
// };

function getSelection(chartSelector) {
  var selectedPoints = $(chartSelector).highcharts().getSelectedPoints();
  var selectedCategories = selectedPoints.map(function (point) { return point.category });
  return selectedCategories;
}
function resetFilters() {
  var stageSelection = $('#stage-chart').highcharts().getSelectedPoints();
  stageSelection.forEach(function (point) { point.select(false) });
  var forecastSelection = $('#forecast-chart').highcharts().getSelectedPoints();
  forecastSelection.forEach(function (point) { point.select(false) });
  var $chosenFilters = $('#owner-filter, #team-filter, #title-filter');
  $chosenFilters.val(null);
  $chosenFilters.trigger('chosen:updated');
};

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
function convert_secs_to_hhmm(secs, includeHrLabel=false) {
    var hours = Math.floor(secs / 3600);
    var mins = Math.floor((secs - hours*3600) / 60);
    return hours + ":" + ("00" + mins).slice(-2) + (includeHrLabel ? (hours > 1 ? " hrs" : " hr") : "" );
}
