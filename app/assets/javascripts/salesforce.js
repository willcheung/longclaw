// Place all the behaviors and hooks related to the matching controller here.
// All this logic will automatically be available in application.js.

// Copied from notifications.js for displaying notifications per project / Smart Task filter functionality
$(document).ready(function() {
    $('#notifications-table').DataTable({
      scrollX: true,
      responsive: true,
      columnDefs: [
        { searchable: false, targets: [0,1,3,4,5,6]},
        { orderable: false, targets: [2,3] },
        { orderDataType: "dom-checkbox", targets: 0 }
      ],
      bPaginate: false,
      order: [[0, "asc"], [ 6, "desc" ]],
      dom:' <"col-sm-4 row"f><"top">t<"col-sm-5"l><"col-sm-5"p><"bottom"i><"clear">',
      language: {
      search: "_INPUT_",
      searchPlaceholder: "Start typing to filter list..."
      }
    });
    $('input[type=search]').attr('size', '50');
});

function toggleSection(toggleSectionParentDOMObj) {
    if (toggleSectionParentDOMObj) {
        toggleSectionParentDOMObj.find(".toggle-icon").toggleClass("fa-caret-right fa-caret-down");
        toggleSectionParentDOMObj.next().next().toggle(400);
    }
};
