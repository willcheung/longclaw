// This is a manifest file that'll be compiled into application.js, which will include all the files
// listed below.
//
// Any JavaScript/Coffee file within this directory, lib/assets/javascripts, vendor/assets/javascripts,
// or vendor/assets/javascripts of plugins, if any, can be referenced here using a relative path.
//
//
//= require jquery
//= require jquery_ujs
//= require ahoy
//= require pace/pace.min.js
//= require slimscroll/jquery.slimscroll.min.js
//= require toastr/toastr.min.js
//= require contextsmith.js
//= require autocomplete.js
//= require best_in_place
//= require best_in_place.jquery-ui
//= require switchery/switchery.js
//= require jstz/jstz.min.js
//= require chosen/chosen.jquery.min.js
//= require selectize/selectize.min.js
//= require d3

/* Ahoy analytics */
ahoy.trackAll();

/* Timezone */
jQuery(function() {
  var tz = jstz.determine();
  $.cookie('timezone', tz.name(), { path: '/' });
});


$(document).ready(function() {

  /* Activating Best In Place */
  jQuery(".best_in_place").best_in_place();

  /* Chosen Select */
  jQuery(".chosen-select").chosen();

  /* Auto resizing textarea */
  jQuery.each(jQuery('textarea[data="autoresize"]'), function() {
    var offset = this.offsetHeight - this.clientHeight;
 
    var resizeTextarea = function(el) {
        jQuery(el).css('height', 'auto').css('height', el.scrollHeight + offset);
    };
    jQuery(this).on('keyup input', function() { resizeTextarea(this); }).removeAttr('data-autoresize');
  });
});

$(document).ready(function() {
  /****************
   Project Modal remote form
   ****************/
  $(document).bind('ajaxError', 'form.new_project', function(event, jqxhr, settings, exception){
    // note: jqxhr.responseJSON undefined, parsing responseText instead
    $(event.data).render_form_errors( $.parseJSON(jqxhr.responseText) );
  });

  $(document).bind('ajaxError', 'form.edit_project', function(event, jqxhr, settings, exception){
    // note: jqxhr.responseJSON undefined, parsing responseText instead
    $(event.data).render_form_errors( $.parseJSON(jqxhr.responseText) );
  });

  /****************
   Account Modal remote form
   ****************/
  $(document).bind('ajaxError', 'form.new_account', function(event, jqxhr, settings, exception){
    // note: jqxhr.responseJSON undefined, parsing responseText instead
    $(event.data).render_form_errors( $.parseJSON(jqxhr.responseText) );
  });

  $(document).bind('ajaxError', 'form.edit_account', function(event, jqxhr, settings, exception){
    // note: jqxhr.responseJSON undefined, parsing responseText instead
    $(event.data).render_form_errors( $.parseJSON(jqxhr.responseText) );
  });

  /****************
   Contact Modal remote form
   ****************/
  $(document).bind('ajaxError', 'form.new_contact', function(event, jqxhr, settings, exception){
    // note: jqxhr.responseJSON undefined, parsing responseText instead
    $(event.data).render_form_errors( $.parseJSON(jqxhr.responseText) );
  });

});

  /****************************
   Modal remote form functions
   ****************************/

(function($) {

  $.fn.modal_success = function(){
    // close modal
    this.modal('hide');

    // clear form input elements
    // todo/note: handle textarea, select, etc
    this.find('form input[type="text"]').val('');

    // clear error state
    this.clear_previous_errors();
  };

  $.fn.render_form_errors = function(errors){
    $form = this;
    this.clear_previous_errors();
    model = this.data('model');

    // show error messages in input form-group help-block
    $.each(errors, function(field, messages){
      $input = $('input[name="' + model + '[' + field + ']"]');
      $input.closest('.form-group').addClass('has-error');
      try {
        $input.closest('.form-group').siblings('.help-block').html( messages.join(' & ') );
      }
      catch (err) {
        // do nothing
      }
    });

  };

  $.fn.clear_previous_errors = function(){
    $('.form-group.has-error', this).each(function(){
      $('.help-block', $(this)).html('');
      $(this).removeClass('has-error');
    });
  }

}(jQuery));

/*
    Converts a number (at least equal to 1) into a human readable string, keeping a certain number of significant digits and discarding the rest (always rounds down).
    Note: Returns 0 for fractional values (absolute values less than 1), and undefined for numbers larger than 999 septillion (10^24-1) or smaller than -999 septillion (-10^24+1).
    Number names refs: http://wiki.answers.com/Q/What_number_is_after_vigintillion&src=ansTT
                       https://en.wikipedia.org/wiki/Names_of_large_numbers
    large_number_to_human_signif_digits(9);        // 9
    large_number_to_human_signif_digits(99);       // 99
    large_number_to_human_signif_digits(199.9);    // 199
    large_number_to_human_signif_digits(1099.9);   // 1.09K
    large_number_to_human_signif_digits(11190);    // 11.1K
    large_number_to_human_signif_digits(103900);   // 103K
    large_number_to_human_signif_digits(104000);   // 104K
    large_number_to_human_signif_digits(104900);   // 104K
    large_number_to_human_signif_digits(1014900);  // 1.01M
*/
function large_number_to_human_signif_digits(number, significant_digits) {
  if (!significant_digits)
    significant_digits = 3;
  if (significant_digits < 0)
    significant_digits = 1;

  if (number == 0 || Math.abs(number) < 1) return 0;
  if (!number || Math.abs(number) > 100000000000000000000000000) return; // 10^24

  var sign = (number < 0) ? "-" : "";
  number = Math.abs(number);
  var s = ['','K', 'M', 'B', 'T', 'Quad', 'Quint', 'Sext', 'Sept'];
  var e = Math.floor(Math.log(number) / Math.log(1000));
  number = truncPrecision(number, significant_digits);
  return sign + (number / Math.pow(1000, e) + "" + s[e]);
}

// currently truncates by transforming into a string, removing the decimal point, taking a substring, then putting the decimal point back in the right place
function truncPrecision(number, significant_digits) {
  var number_str = number + "";
  var decimal_pos = number_str.search("\\.");
  if (decimal_pos == -1) {
    decimal_pos = number_str.length;
  }
  var number_str_transform = number_str.replace(".","");  // remove the decimal pt
  number_str_transform = number_str_transform.substring(0, significant_digits);  // truncate to significant_digits digits

  if (decimal_pos >= 0 && decimal_pos <= 3) {
    return Number(number_str_transform.substring(0,decimal_pos) + "." + number_str_transform.substring(decimal_pos,number_str_transform.length));
  } else {
    var factor_adjust = (decimal_pos >= 3 ? decimal_pos : number_str.length) - significant_digits;
    return number_str_transform * Math.pow(10, factor_adjust);
  }
}

// Formats a number into a string with commas (,) placed as thousands separators.
function numberWithCommas(n) {
  return n.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}