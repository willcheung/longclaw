$(document).ready(function() {
/* Autocomplete for search bar using jQuery UI*/
  // $("#search").autocomplete({
  //   autoFocus: true,
  //   delay: 300,
  //   source: function (request, response) {
  //     if (request.term[0] === "#") {
  //       $.get(window.location.origin + "/search/autocomplete_project_name.json?term=" + request.term.slice(1), function (data) {
  //         response(data);
  //       }, "json");
  //     }
  //   }
  // });
/* Autocomplete for search bar using tokenInput */
  // $("#search").tokenInput(window.location.origin + "/search/autocomplete_project_name.json", {
  //   queryParam: "term",
  //   theme: "mac"
  // });

  // $("#search").keyup(function () {
  //   console.log($("#search").getCursorPosition());
  //   console.log($("#search").val());
  // })

  $("#search").textcomplete([
    {
      // RegEx for PROJECT strategy, #project-name
      match: /(^|\s)#(\w*)$/,
      search: function (term, callback) {
        $.getJSON('/search/autocomplete_project_name.json', { term: term })
          .done( function (data) {
            callback(data);
            console.log(data);
          })
          .fail( function () {
            callback([]);
          })
      },
      replace: function (value) {
        return '$1#' + value.name + ' ';
      },
      template: function (value) {
        return value.name;
      }
    }
  ], { zIndex: '1000', debounce: 300 }).overlay([
    {
      match: /\B#\w+/g,
      css: {
        'background-color': '#8CD5B7'
      }
    }
  ]);

});


// (function($) {
//     $.fn.getCursorPosition = function() {
//         var input = this.get(0);
//         if (!input) return; // No (input) element found
//         if (input.selectionStart || input.selectionStart == '0') {
//             // Standard-compliant browsers
//             return input.selectionStart;
//         } else if (document.selection) {
//             // IE
//             input.focus();
//             var sel = document.selection.createRange();
//             var selLen = document.selection.createRange().text.length;
//             sel.moveStart('character', -input.value.length);
//             return sel.text.length - selLen;
//         }
//     }
// })(jQuery);