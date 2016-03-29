$(document).ready(function() {

/* Autocomplete and Tokenization for search bar using Selectize */
  $("#search").selectize({
    closeAfterSelect: true,
    valueField: 'id',
    labelField: 'name',
    searchField: ['name'],
    create: false,
    score: function(term) {
      // remove leading character when filtering and scoring autocomplete options (will be a #)
      var score = this.getScoreFunction(term.slice(1));
      return function(item) {
        return score(item);
      };
    },
    load: function (term, callback) {
      if (!term.length) return callback()
      // use # to search for projects by name
      if (term[0] === '#') {
        $.getJSON( '/search/autocomplete_project_name.json?term=' + encodeURIComponent(term.slice(1)) )
          .done( function (data) {
            callback(data);
          })
          .fail( function () {
            callback();
          })
      }
    },
    onDropdownOpen: function ($dropdown) {
      // Manually prevent dropdown from opening when:
      // 1. There is no search term, or
      // 2. The search term does not begin with #
      if (!this.lastQuery.length || this.lastQuery[0] !== '#') {
        this.close();
      }
    }
  })

  // var selectize = $select[0].selectize;
  // selectize.on("dropdown_open", function () {
  // })

});