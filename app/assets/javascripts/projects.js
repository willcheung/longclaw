// Place all the behaviors and hooks related to the matching controller here.
// All this logic will automatically be available in application.js.

// Copied from notifications.js for displaying notifications per project
//= require datepicker/bootstrap-datepicker.js
//= require iCheck/icheck.min.js

jQuery(document).ready(function($) {

	$('.switch').on('click', function(e) {    
	    var trigger = $(this);
	 
	    if ( !trigger.hasClass('active') ) {
	      $('#loader').find('.loader-icon').addClass('hidden').filter('[data-cog*="' +  trigger.data('trigger') + '"]').removeClass('hidden');
	      trigger.addClass('active').siblings('.active').removeClass('active'); 
	    }
	    e.preventDefault();
	  });

	$('.start_date_datepicker').datepicker({
	  keyboardNavigation: false,
	  todayHighlight: true,
	  autoclose: true
	});


  //DataTables
  $('#projects-table').DataTable( {
    responsive: true,
    columnDefs: [
      { searchable: false, targets: [0,4,5,6,7,8,9,10]},
      { orderable: false, targets: [0,4,5,7,9,10] }
    ],
    "order": [[ 1, "asc" ]],
    "lengthMenu": [[50, 100, -1], [50, 100, "All"]],
    "dom":' <"col-sm-4 row"f><"top">rt<"col-sm-5"l><"col-sm-5"p><"bottom"i><"clear">',
    "language": {
      search: "_INPUT_",
      searchPlaceholder: "Start typing to filter list..."
    }
  } );

  $('input[type=search]').attr('size', '50');

  /* Rendering object for defining how search-subs and member-search displays search results */
  var renderContacts = {
    item: function(item, escape) {
      return '<div>' +
          (item.name ? '<span class="name">' + escape(item.name) + '</span>' : '') +
          (item.email ? '<span class="email">' + escape(item.email) + '</span>' : '') +
      '</div>';
    },
    option: function(item, escape) {
      var label = item.name || item.email;
      var caption = item.name ? item.email : null;
      return '<div>' +
          '<span class="label">' + escape(label) + '</span>' +
          (caption ? '<span class="caption">' + escape(caption) + '</span>' : '') +
      '</div>';
    }
  }

  /* Selectize for autocompleting possible subscribers */
  $("#search-subs").selectize({
    closeAfterSelect: true,
    valueField: 'id',
    labelField: 'name',
    searchField: ['name', 'email'],
    create: false,
    render: renderContacts,
    load: function (term, callback) {
      if (!term.length) return callback()
      $.getJSON( '/search/autocomplete_project_subs.json', { project_id: window.location.pathname.slice(10) } )
        .done( function (data) {
          callback(data);
        })
        .fail( function () {
          callback();
        })
    },
    onBlur: function () {
      // Manually prevent input box from being cleared on blur
      this.setTextboxValue(this.lastQuery);
    }
  })

  /* Selectize for autocompleting possible members */
  $("#member-search").selectize({
    closeAfterSelect: true,
    valueField: 'email',
    labelField: 'name',
    searchField: ['name', 'email'],
    create: false,
    render: renderContacts,
    load: function (term, callback) {
      if (!term.length) return callback()   
      $.getJSON( '/search/autocomplete_project_member.json', { term: encodeURIComponent(term) } )
        .done( function (data) {
          callback(data);
        })
        .fail( function () {
          callback();
        })
      
    },
    onBlur: function () {
      // Manually prevent input box from being cleared on blur
      this.setTextboxValue(this.lastQuery);
    }
  })

  $("#search-account-projects").chosen()


  $('.bulk-project').change(function(){
    if($(this).is(":checked")){
      checkCounter++;
    }
    else{
      checkCounter--;
    }

    if(checkCounter>0)
    {
      // $('.bulk-group').css('visibility','visible');
      $('#bulk-delete').prop("disabled",false);
      $('#bulk-owner').prop("disabled",false).trigger("chosen:updated");
      $('#bulk-type').prop("disabled",false).trigger("chosen:updated");
    }
    else
    {
      // $('.bulk-group').css('visibility','hidden');
      $('#bulk-delete').prop("disabled",true);
      $('#bulk-owner').prop("disabled",true).trigger("chosen:updated");
      $('#bulk-type').prop("disabled",true).trigger("chosen:updated");
    }
    // console.log(checkCounter);

  });

  $('#bulk-delete').click(function(){
    bulkOperation("delete",  null, "/project_bulk");
    window.location.replace("/projects");
  });

  $('.category_box').chosen({ disable_search: true, allow_single_deselect: true});
  $('.category_box').on('change',function(evt,params){
      bulkOperation("category",  params["selected"], "/project_bulk");
      window.location.replace("/projects");     
  });

  $('.owner_box').chosen({ allow_single_deselect: true});
  $('.owner_box').on('change',function(evt,params){
      bulkOperation("owner",  params["selected"], "/project_bulk");
      window.location.replace("/projects");     
  });


  $('.category_filter').chosen({ disable_search: true, allow_single_deselect: true});
  $('.category_filter').on('change',function(evt,params){
    var taskType="";
    if(params){
        window.location.replace("/projects?type="+params["selected"]);    
    }
    else{
      window.location.replace("/projects");
    }
  });


  $('.filter-group, .bulk-group').hover(function(){
    $('.chosen-container-single').css('cursor', 'pointer');
    $('.chosen-single').css('cursor', 'pointer'); 
  });


});


var checkCounter = 0;

function bulkOperation(operation, value, url){
  var array = [];
  var i = 0;
  $('.bulk-project:checked').each(function(){
    array[i] = $(this).val();
    i++;
  }); 
  
  var temp = {
    selected: array,
    operation: operation,
    value: value
  };

  msg= JSON.stringify(temp);
  // console.log(msg);
  $.ajax({
      type: "POST",
      url: url,
      contentType: 'application/json',
      dataType: 'json',
      data: msg
  });
}

// Copied from notifications.js for displaying notifications per project

$(document).ready(function() {
    $('#notifications-table').DataTable({
      scrollX: true,
      responsive: true,
      columnDefs: [
        { searchable: false, targets: [0,1,3,4,5,6]},
        { orderable: false, targets: [2,3] },
        { orderDataType: "dom-checkbox", targets: 0 }
      ],
      bPaginate: false,
      order: [[0, "asc"], [ 6, "desc" ]],
      dom:' <"col-sm-4 row"f><"top">t<"col-sm-5"l><"col-sm-5"p><"bottom"i><"clear">',
      language: {
      search: "_INPUT_",
      searchPlaceholder: "Start typing to filter list..."
      }
    });
    $('input[type=search]').attr('size', '50');
});

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

$('.tool-tip-category').tooltip({   
    title: "<p style=\"line-height:20px;\"><b>Smart Action:</b> Tasks with due dates that are automatically detected from the email body.<br>"+
           "<b>Risk:</b> Negative sentiment detected in email body.<br>"+
           "<b>Opportunity:</b> Projects streams that have been inactive for 30+ days and is an opportunity to follow up.<br>"+
           "<b>To-do:</b> Manually generated task.<p>",
    html: true,
    container: 'body'
});

$('[data-toggle="overdue"]').tooltip();   

$('[data-toggle="overdue"]').hover(function(){
    $('.tooltip-inner').css('max-width', '64px');
    $('.tooltip-inner').css('padding', '2px 2px');
    $('.tooltip-inner').css('opacity', '1');
    $('.tooltip-inner').css('background-color', 'grey');
    $('.tooltip-inner').css('color', 'white');
    
    $('.tooltip-arrow').css('opacity', '0');
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
    $('.tooltip-inner').css('color', 'black');
    $('.tooltip-inner').css('opacity', '1');
    $('.tooltip-inner').css('padding', '20px');
    $('.tooltip-inner').css('max-width', '512px');
    $('.tooltip-inner').css('text-align', 'left');
    
    $('.tooltip').css('background-color', 'white');
    $('.tooltip').css('opacity', '1');
    $('.tooltip').css('border-style','solid');
    $('.tooltip').css('border-width', '1px');
    $('.tooltip').css('border-color', '#eeeeee');
    $('.tooltip').css('boxShadow', '0px 0px 40px #aaaaaa');

    $('.tooltip-inner-content').css('margin-bottom', '7px');
    $('.tooltip-arrow').css('opacity', '0');
});
