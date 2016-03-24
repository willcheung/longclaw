/* Autocomplete for search bar */
$(document).ready(function() {
  $("#search").autocomplete({
    autoFocus: true,
    delay: 300,
    source: function (request, response) {
      if (request.term[0] === "#") {
        $.get(window.location.origin + "/search/autocomplete_project_name.json?term=" + request.term.slice(1), function (data) {
          response(data);
        }, "json");
      }
    },
    select: function (event, ui) {
      console.log(event);
      console.log(ui);
    }
  });
});