$(document).ready(function() {

/* Autocomplete and Tokenization for search bar using Selectize */
  $("#search").selectize({
    closeAfterSelect: true,
    valueField: 'id',
    labelField: 'name',
    searchField: ['name'],
    create: false,
    render: {
      item: function(item, escape) {
        return '<div>' +
            (item.name ? '<span class="name">' + escape(item.name) + '</span>' : '') +
            (item.account ? '<span class="account">' + escape(item.account) + '</span>' : '') +
        '</div>';
      },
      option: function(item, escape) {
        var label = item.name || item.account;
        var caption = item.name ? item.account : null;
        return '<div>' +
            '<span class="label">' + escape(label) + '</span>' +
            (caption ? '<span class="caption">' + escape(caption) + '</span>' : '') +
        '</div>';
      }
    },
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
        $.getJSON( '/search/autocomplete_project_name.json', { term: encodeURIComponent(term.slice(1)) } )
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
      // 3. At least one project has been selected already
      if (!this.lastQuery.length || this.lastQuery[0] !== '#' || this.items.length) {
        this.close();
      }
    },
    onBlur: function () {
      // Manually prevent input box from being cleared on blur
      this.setTextboxValue(this.lastQuery);
    }
  });

  // Manually add query text to search parameters
  $("#search-form").submit(function (event) {
    var query = $("#search")[0].selectize.lastQuery;
    $("#query-term").val(query);
    if ($("#search").val()) {
      $(this).removeAttr("data-remote");
      $(this).removeData("remote");
      $(".fa-search").addClass("fa-spinner fa-pulse")
    }
  })

  $("#search-subs").selectize({
    closeAfterSelect: true,
    valueField: 'id',
    labelField: 'name',
    searchField: ['name', 'email'],
    create: false,
    render: renderContacts,
    load: function (term, callback) {
      if (!term.length) return callback()
      $.getJSON( '/search/autocomplete_project_subs.json', { project_id: window.location.pathname.slice(10) } )
        .done( function (data) {
          callback(data);
        })
        .fail( function () {
          callback();
        })
    },
    onBlur: function () {
      // Manually prevent input box from being cleared on blur
      this.setTextboxValue(this.lastQuery);
    }
  })

  $("#member-search").selectize({
    closeAfterSelect: true,
    valueField: 'email',
    labelField: 'name',
    searchField: ['name', 'email'],
    create: false,
    render: renderContacts,
    load: function (term, callback) {
      if (!term.length) return callback()   
      $.getJSON( '/search/autocomplete_project_member.json', { term: encodeURIComponent(term) } )
        .done( function (data) {
          callback(data);
        })
        .fail( function () {
          callback();
        })
      
    },
    onBlur: function () {
      // Manually prevent input box from being cleared on blur
      this.setTextboxValue(this.lastQuery);
    }
  })

});

var renderContacts = {
  item: function(item, escape) {
    return '<div>' +
        (item.name ? '<span class="name">' + escape(item.name) + '</span>' : '') +
        (item.email ? '<span class="email">' + escape(item.email) + '</span>' : '') +
    '</div>';
  },
  option: function(item, escape) {
    var label = item.name || item.email;
    var caption = item.name ? item.email : null;
    return '<div>' +
        '<span class="label">' + escape(label) + '</span>' +
        (caption ? '<span class="caption">' + escape(caption) + '</span>' : '') +
    '</div>';
  }
}