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