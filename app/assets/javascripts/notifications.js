// Place all the behaviors and hooks related to the matching controller here.
// All this logic will automatically be available in application.js.

//= require datepicker/bootstrap-datepicker.js
//= require iCheck/icheck.min.js

$(document).ready(function() {
    $('#notifications-table').DataTable({
    	responsive: true,
	    columnDefs: [
	      { searchable: false, targets: [0,1,3,4,5,6,7]},
	      { orderable: false, targets: [0,1,2,3] }
	    ],
	    "bPaginate": false,
	    "order": [[ 7, "desc" ]],
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
  $(this).parent().parent().parent().css('opacity', '0.5');
  $.ajax({url:'/notifications/'+$(this).attr('id')+'/update_is_complete'});
  
});


$('input').on('ifUnchecked', function(event){
  $(this).parent().parent().parent().attr("bgcolor", "");
  $(this).parent().parent().parent().css('opacity', '1');
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
   
    if(id in cachedData){
        return cachedData[id];
    }

    var localData = "error";

   $.ajax('/notifications/show_email_body/'+id, {
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


function removeParam(search, keyword){
    if(search.length==0) return search;

    var params = search.split("&");
    var result = "";

    for(i=0; i<params.length; i++){
        var param = params[i].split("=");
        if(param[0].length>0 && param[0]!==keyword){
            result += params[i] + "&";
        }
    }

    if(result[result.length-1]==="&") return result.substring(0,result.length-1);
    else return result;

}

function newURL(search,selectType, newParam){
    // always remove & in the back or it will cause error
    var finalURL = "";
    var newsearch="";

    //always set to type=incomplete when search string is empty
    if(search.length==0){
        search = "?type=incomplete";
    }
    
    original = removeParam(search.substring(1), selectType);

    if(original.length==0){   
        newsearch = newParam;
    }
    else{
        if(newParam.length==0){
            // when user press X, newParam will be ""
            newsearch = original;
        }
        else{
            newsearch = original + "&" + newParam;
        }
    }

    if(newsearch.length==0){
        finalURL = "/notifications";
    }
    else{
        finalURL = "/notifications/?"+newsearch;
    }

    // console.log(finalURL);
    window.location.replace(finalURL);

}

$('.is_complete_box').chosen({width: "150px", disable_search: true, allow_single_deselect: true});

$('.filter_section').hover(function(){
    $('.chosen-container-single').css('cursor', 'pointer');
    $('.chosen-single').css('cursor', 'pointer'); 
});


$('.is_complete_box').on('change',function(evt,params){

    var taskType="";

    if(params){
        switch(params["selected"]){
            case "1":
                taskType = "type=incomplete";
                break;
            case "2":
                taskType = "type=complete";
                break;
            default:
                break;
        }
    }
    else{
        taskType = "type=all";
    }

    newURL(window.location.search,"type", taskType);
        
});

$('.assignee_box').chosen({width: "150px", disable_search: true, allow_single_deselect: true});

$('.assignee_box').on('change',function(evt,params){

    var taskType="";

    if(params){
        switch(params["selected"]){
            case "1":
                taskType = "assignee=me";
                break;
            case "2":
                taskType = "assignee=none";
                break;
            default:
                break;
        }
    }

    newURL(window.location.search,"assignee", taskType);
        
});


$('.due_date_box').chosen({width: "150px", disable_search: true, allow_single_deselect: true});

$('.due_date_box').on('change',function(evt,params){

    var taskType="";

    if(params){
        switch(params["selected"]){
            case "1":
                taskType = "duedate=oneweek";
                break;
            case "2":
                taskType = "duedate=none";
                break;
            default:
                break;
        }
    }

    newURL(window.location.search,"duedate", taskType);
      
});

