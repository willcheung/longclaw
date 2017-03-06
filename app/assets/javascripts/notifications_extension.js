//= require iCheck/icheck.min.js

// Checking/Unchecking Tasks
$('.i-checks').iCheck({
  checkboxClass: 'icheckbox_square-green'
});

$(document).on('ifChecked', 'input', function(event){
  // $(this).parent().parent().parent().attr("bgcolor", "#eeeeee");
  // $(this).parent().parent().parent().css('opacity', '0.5');
  $.ajax({url:'/notifications/'+$(this).attr('id')+'/update_is_complete'});

  // var target = '#notification_row_'+$(this).attr('id');
  // $(target).fadeOut();
});


$(document).on('ifUnchecked', 'input', function(event){
  // $(this).parent().parent().parent().attr("bgcolor", "");
  // $(this).parent().parent().parent().css('opacity', '1');
  $.ajax({url:'/notifications/'+$(this).attr('id')+'/update_is_complete'});
});