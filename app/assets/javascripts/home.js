//= require datepicker/bootstrap-datepicker.js
//= require iCheck/icheck.min.js

jQuery(document).ready(function($) {  
  //DataTables
    $('#projects-table').DataTable( {
      responsive: true,
      searching: false,
      columnDefs: [
        { orderable: false, targets: [0,7] }
      ],
      "order": [[ 1, "asc" ]],
      "lengthMenu": [[50, 100, -1], [50, 100, "All"]],
      "dom":' <"col-sm-4 row"f><"top">rt<"col-sm-5"l><"col-sm-5"p><"bottom"i><"clear">'
    } );
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

  var target = '#notification_row_'+$(this).attr('id');
  $(target).fadeOut();
  
});


$('input').on('ifUnchecked', function(event){
  $(this).parent().parent().parent().attr("bgcolor", "");
  $(this).parent().parent().parent().css('opacity', '1');
  $.ajax({url:'/notifications/'+$(this).attr('id')+'/update_is_complete'});
});