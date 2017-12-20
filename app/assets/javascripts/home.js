//= require highcharts-sparkline/highcharts-sparkline

$('[data-toggle="tooltip"]').tooltip();

jQuery(document).ready(function($) {  
  //DataTables
    $('#projects-table').DataTable( {
      // responsive: true,
      searching: false,
      scrollX: true,
      fixedColumn: true,
      columnDefs: [
        { orderable: false, targets: [5,9,12] }
      ],
      "order": [[ 0, "asc" ]],
      "lengthMenu": [[50, 100, -1], [50, 100, "All"]],
      "dom":' <"col-sm-4 row"f><"top">rt<"col-sm-5"l><"col-sm-5"p><"bottom"i><"clear">'
    });

  $('#close-date-filter')
    .chosen({ disable_search: true, allow_single_deselect: true})
    .change( function () {
      let params = {};
      if ($(this).val()) {
        params.close_date = $(this).val();
      }
      window.location.search = $.param(params);
    })

    $('.filter-group').hover(function () {
      $('.chosen-container-single').css('cursor', 'pointer');
      $('.chosen-single').css('cursor', 'pointer');
    });
});