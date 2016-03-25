$(document).ready(function() {
    $('#users-table').DataTable( {
        "scrollX": true,
        "responsive": true,
        "lengthMenu": [[50, 100, -1], [50, 100, "All"]],
        "dom":' <"col-sm-4 row"f><"top">rt<"col-sm-5"l><"col-sm-5"p><"bottom"i><"clear">',
        "language": {
		      search: "_INPUT_",
		      searchPlaceholder: "Start typing to filter list..."
		    }
    } );
    
    $('input[type=search]').attr('size', '50');
} );