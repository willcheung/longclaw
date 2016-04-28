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


$('.hoverToolTip').tooltip({
    title: hoverGetData,
    html: true,
    container: 'body',
});


var cachedData = Array();

function hoverGetData(){
    var element = $(this);

    var id = element.data('id');
    var conversationID = element.data('conversationid');
    var projectID = element.data('projectid');
    var messageID = element.data('messageid');

    // console.log(conversationID);
    // console.log(projectID);
    // console.log(messageID);

    if(id in cachedData){
        return cachedData[id];
    }

    var localData = "error";

    $.ajax('/notifications/show_email_body/'+id+'?conversation_id='+encodeURIComponent(conversationID)+'&message_id='+encodeURIComponent(messageID)+'&project_id='+ (projectID), {
        async: false,
        success: function(data){
            localData = data;
        }
    });

    cachedData[id] = localData;

    return localData;
}

$('.hoverToolTip').hover(function(){
    $('.tooltip-inner').css('background-color', 'white');
    $('.tooltip-inner').css('opacity', '1');
    
    $('.tooltip').css('background-color', 'white');
    $('.tooltip').css('opacity', '1');
    $('.tooltip').css('border-style','solid');
    $('.tooltip').css('border-width', '1px');
    $('.tooltip').css('border-color', '#eeeeee');
    $('.tooltip').css('boxShadow', '0px 0px 40px #aaaaaa');

    $('.tooltip-inner-content').css('margin-bottom', '7px');
    $('.tooltip-arrow').css('opacity', '0');



});