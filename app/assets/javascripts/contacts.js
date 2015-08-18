
$(document).ready(function(){
  //DataTables
  $('#contacts-table').DataTable( {
    responsive: true,
    columnDefs: [
    { searchable: false, targets: [4,5,6]}],
    "lengthMenu": [[50, 100, -1], [50, 100, "All"]],
    "dom":' <"col-sm-4 row"f><"top">rt<"col-sm-4"l><"col-sm-6"p><"bottom"i><"clear">',
    "language": {
      search: "_INPUT_",
      searchPlaceholder: "Start typing to filter list..."
    }
  } );

  $('#contacts-table_filter').prepend($('input[type=search]'));
  $('input[type=search]').attr('size', '50');

});

