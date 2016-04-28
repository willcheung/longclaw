// Place all the behaviors and hooks related to the matching controller here.
// All this logic will automatically be available in application.js.

//= require datepicker/bootstrap-datepicker.js

$(document).ready(function() {
    $('#notifications-table').DataTable({
    	responsive: true,
	    columnDefs: [
	      { searchable: false, targets: [0,1,3,4,5]},
	      { orderable: false, targets: [0,1,2] }
	    ],
	    "bPaginate": false,
	    "order": [[ 6, "desc" ]],
	    "dom":' <"col-sm-4 row"f><"top">rt<"col-sm-5"l><"col-sm-5"p><"bottom"i><"clear">',
	    "language": {
      search: "_INPUT_",
      searchPlaceholder: "Start typing to filter list..."
    	}
    });
    $('input[type=search]').attr('size', '50');
} );

$(function() {
    $('.i-checks').iCheck({
        checkboxClass: 'icheckbox_square-green'
    });
});

$('input').on('ifChecked', function(event){
  $(this).parent().parent().parent().attr("bgcolor", "#eeeeee");
  $.ajax({url:'/notifications/'+$(this).attr('id')+'/update_is_complete'});
  // var temp = "#best_in_place_notification_" + $(this).attr('id') + "_name"
  // $(temp).css({'display' : 'inline-block'});
});


$('input').on('ifUnchecked', function(event){
  $(this).parent().parent().parent().attr("bgcolor", "");
  $.ajax({url:'/notifications/'+$(this).attr('id')+'/update_is_complete'});
});

jQuery(function($){
    $.datepicker.regional['ca'] = {
        dateFormat: 'yy-mm-dd',
        firstDay: 1,
        isRTL: false,
        showMonthAfterYear: false,
        yearSuffix: ''};
    $.datepicker.setDefaults($.datepicker.regional['ca']);
});