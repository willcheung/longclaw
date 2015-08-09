
$(document).ready(function(){
  //DataTables
  $('#accounts-table').DataTable( {
    responsive: true,
    columnDefs: [
    { searchable: false, targets: [4,5]}],
    "lengthMenu": [[50, 100, -1], [50, 100, "All"]],
    "dom":' <"col-sm-4 row"f><"top">rt<"col-sm-5"l><"col-sm-5"p><"bottom"i><"clear">',
    "language": {
      search: "_INPUT_",
      searchPlaceholder: "Start typing to filter list..."
    }
  } );

  $('#accounts-table_filter').prepend($('input[type=search]'));
  $('input[type=search]').attr('size', '50');

  // edit button hover-over effect
  // $('#accounts-table').
  // on('mouseover', 'tr', function() {
  //   jQuery(this).find('.edit').show();
  // }).
  // on('mouseout', 'tr', function() {
  //   jQuery(this).find('.edit').hide();
  // });

  /****************
   Modal remote form
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