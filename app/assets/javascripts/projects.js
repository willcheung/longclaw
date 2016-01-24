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

});
