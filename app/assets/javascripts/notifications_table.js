//= require iCheck/icheck.min.js

// Checking/Unchecking Tasks
$('.i-checks').iCheck({
  checkboxClass: 'icheckbox_square-green'
});

$(document).on('ifChecked', 'input', function(event){
  $(this).parent().parent().parent().attr("bgcolor", "#eeeeee");
  $(this).parent().parent().parent().css('opacity', '0.5');
  $.ajax({url:'/notifications/'+$(this).attr('id')+'/update_is_complete'});

  var target = '#notification_row_'+$(this).attr('id');
  $(target).fadeOut();
});


$(document).on('ifUnchecked', 'input', function(event){
  $(this).parent().parent().parent().attr("bgcolor", "");
  $(this).parent().parent().parent().css('opacity', '1');
  $.ajax({url:'/notifications/'+$(this).attr('id')+'/update_is_complete'});
});

/*
  WARNING: For tooltip stuff below, DO NOT try to load after document is ready.
  Current setup uses Bootstrap tooltip, NOT the jQuery UI tooltip (2016/10/21)
  js loaded in this order: bootstrap.js ... this ... jquery-ui.js
  Therefore when document is ready, jQuery UI tooltip overwrites the Bootstrap tooltip in global namespace since jQuery UI is loaded after
  Tooltip initialization must occur after bootstrap.js but before jquery-ui.js
*/
// Tooltips
$('.tool-tip-category').tooltip({
  title: "<p style=\"line-height:20px;\"><b>Alert:</b> Negative sentiment detected in e-mail body.<br>"+
         "<b>To-do:</b> Manually generated task.<p>",
  html: true,
  container: 'body'
});

$('.tool-tip-category').hover(function(){
  $('.tooltip-inner').css('max-width', '600px');
  $('.tooltip-inner').css('padding', '2px 2px');
  $('.tooltip-inner').css('opacity', '1');
  $('.tooltip-inner').css('background-color', '#2f4050');
  $('.tooltip-inner').css('color', 'white');

  $('.tooltip-arrow').css('opacity', '0');

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

// E-mail Preview Tooltip
$('.hoverToolTip').tooltip({
  title: hoverGetData,
  html: true,
  container: 'body'
});

var cachedData = Array();

function hoverGetData() {
  console.log('hoverGetData')
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
  $('.tooltip-inner').css('padding', '20px 20px');
  $('.tooltip-inner').css('max-width', '512px');
  $('.tooltip-inner').css('text-align', 'left');

  $('.tooltip').css('background-color', 'white');
  $('.tooltip').css('opacity', '1');
  $('.tooltip').css('border-style','solid');
  $('.tooltip').css('border-width', '1px');
  $('.tooltip').css('border-color', '#eeeeee');
  $('.tooltip').css('boxShadow', '0px 0px 20px #aaaaaa');

  $('.tooltip-inner-content').css('margin-bottom', '7px');
  $('.tooltip-arrow').css('opacity', '0');
});
