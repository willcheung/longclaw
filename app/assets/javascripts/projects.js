//= require datepicker/bootstrap-datepicker.js

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
      { searchable: false, targets: [4,5,6,7,8]},
      { orderable: false, targets: [3,4,5,7,8] }
    ],
    "lengthMenu": [[50, 100, -1], [50, 100, "All"]],
    "dom":' <"col-sm-4 row"f><"top">rt<"col-sm-5"l><"col-sm-5"p><"bottom"i><"clear">',
    "language": {
      search: "_INPUT_",
      searchPlaceholder: "Start typing to filter list..."
    }
  } );

  $('input[type=search]').attr('size', '50');


});
