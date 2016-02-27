
$(document).ready(function(){
  //DataTables
  $('#accounts-table').DataTable( {
    responsive: true,
    columnDefs: [
      { searchable: false, targets: [2,3,6]},
      { orderable: false, targets: 6 }
    ],
    "lengthMenu": [[50, 100, -1], [50, 100, "All"]],
    "dom":' <"col-sm-4 row"f><"top">rt<"col-sm-5"l><"col-sm-5"p><"bottom"i><"clear">',
    "language": {
      search: "_INPUT_",
      searchPlaceholder: "Start typing to filter list..."
    }
  } );

  $('#accounts-table_filter').prepend($('input[type=search]'));
  $('input[type=search]').attr('size', '50');

});

