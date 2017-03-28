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
      $input.closest('.form-group').siblings('.help-block').html( messages.join(' & ') );
    });

  };

  $.fn.clear_previous_errors = function(){
    $('.form-group.has-error', this).each(function(){
      $('.help-block', $(this)).html('');
      $(this).removeClass('has-error');
    });
  }

}(jQuery));