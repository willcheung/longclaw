var checkedAccountIds = [];

$('[data-toggle="tooltip"]').tooltip();

$(document).ready(function(){
  
  $('#bulk-category').chosen({ disable_search: true, allow_single_deselect: true});
  $('#bulk-owner').chosen({ allow_single_deselect: true});
  
  $('.category_filter').chosen({ disable_search: true, allow_single_deselect: true});

  //DataTables
  $('#accounts-table').DataTable( {
    responsive: true,
    columnDefs: [
      { searchable: false, targets: [0,4,5]},
      { orderable: false, targets: [0] }
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

  $('.filter-group, .bulk-group').hover(function(){
    $('.chosen-container-single').css('cursor', 'pointer');
    $('.chosen-single').css('cursor', 'pointer'); 
  });

  /* Handle bulk action */
  $('#accounts-table tbody').on('change', '.bulk-account', function () {
    if ($(this).prop("checked")) {
      checkedAccountIds.push($(this).val());
    }
    else {
      var i = checkedAccountIds.indexOf($(this).val());
      if (i !== -1) {
        checkedAccountIds.splice(i, 1);
      }
    }

    if (checkedAccountIds.length > 0) {
      $('.bulk-action').prop("disabled",false).trigger('chosen:updated');
    }
    else {
      $('.bulk-action').prop("disabled",true).trigger('chosen:updated');
    }
  });

  $('#bulk-delete').click(function(){
    bulkOperation("delete",  null);
  });

  $('select.bulk-action').chosen().change( function (evt, params) {
    var op = $(this).prop('id').substring(5);
    bulkOperation(op, params.selected);
  });

  $('.category_filter').on('change',function(evt,params){
    var taskType="";
    if(params){
        window.location.replace("/accounts?account_type="+params["selected"]);    
    }
    else if(typeof(params) == 'undefined') {
      taskType = "none";
      window.location.replace("/accounts?account_type="+taskType);  
    }
    else{
      window.location.replace("/accounts");
    }
  });

});

function bulkOperation (operation, value) {
  var temp = {
    account_ids: checkedAccountIds,
    operation: operation,
    value: value
  };

  var data = $.param(temp);

  $.post("/account_bulk", data, 'json')
    .done(function () {
      window.location.replace(document.location.href); // reload page, keep filter params
    })
    .fail(function () {
      console.log("bulk error");
    });
}