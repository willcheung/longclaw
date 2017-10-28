//= require highcharts-sparkline/highcharts-sparkline.js

var checkedProjectIds = [];
var URL_PREFIX = "/projects";

$('[data-toggle="tooltip"]').tooltip();

$(document).ready(function($) {

  $("#search-account-projects").chosen();
  $('#bulk-category').chosen({ disable_search: true, allow_single_deselect: true});
  $('#bulk-owner').chosen({ allow_single_deselect: true});
  $('#bulk-status').chosen({ disable_search: true, allow_single_deselect: true});
  $('.category_filter').chosen({ disable_search: true, allow_single_deselect: true});

	$('.switch').on('click', function(e) {
	    var trigger = $(this);

	    if ( !trigger.hasClass('active') ) {
	      $('#loader').find('.loader-icon').addClass('hidden').filter('[data-cog*="' +  trigger.data('trigger') + '"]').removeClass('hidden');
	      trigger.addClass('active').siblings('.active').removeClass('active');
	    }
	    e.preventDefault();
	  });

  /* Toggle Show Expandable Sections (i.e., "Details", "Daily Followers", etc.) */
  $('.toggle-open').click( function () {
      toggleSection($(this));
  })


  //DataTables
  $('#projects-table').DataTable({
    responsive: true,
    columnDefs: [
      { searchable: false, targets: [0,6,7,8,9,10,11,12] },
      { orderable: false, targets: [0,6,9,12,13] }
    ],
    "order": [[ 1, "asc" ]],
    "lengthMenu": [[50, 100, -1], [50, 100, "All"]],
    "dom":' <"col-sm-4 row"f><"top">rt<"col-sm-5"l><"col-sm-5"p><"bottom"i><"clear">',
    "language": {
      search: "_INPUT_",
      searchPlaceholder: "Start typing to filter list..."
    }
  });

  $('input[type=search]').attr('size', '50');

  /* Rendering object for defining how search-*-subs and member-search displays search results */
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

  /* Selectize for autocompleting possible daily subscribers */
  $(".search-daily-subs").selectize({
    closeAfterSelect: true,
    valueField: 'id',
    labelField: 'name',
    searchField: ['name', 'email'],
    create: false,
    render: renderContacts,
    load: function (term, callback) {
      if (!term.length) return callback()
      $.getJSON( '/search/autocomplete_project_subs.json', { project_id: window.location.pathname.slice(10), type: "daily" } )
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
  /* Now, selectize for autocompleting possible weekly subs */
  $(".search-weekly-subs").selectize({
    closeAfterSelect: true,
    valueField: 'id',
    labelField: 'name',
    searchField: ['name', 'email'],
    create: false,
    render: renderContacts,
    load: function (term, callback) {
      if (!term.length) return callback()
      $.getJSON( '/search/autocomplete_project_subs.json', { project_id: window.location.pathname.slice(10), type: "weekly" } )
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

  /* Selectize for autocompleting possible members */
  $("#member-search").selectize({
    closeAfterSelect: true,
    valueField: 'email',
    labelField: 'name',
    searchField: ['name', 'email'],
    create: false,
    render: renderContacts,
    load: function (term, callback) {
      if (!term.length) return callback()
      $.getJSON( '/search/autocomplete_project_member.json', { project_id: window.location.pathname.slice(10) } )
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


  /* Handle bulk action */
  $('#projects-table tbody').on('change', '.bulk-project', function () {
    if ($(this).prop("checked")) {
      checkedProjectIds.push($(this).val());
    }
    else {
      var i = checkedProjectIds.indexOf($(this).val());
      if (i !== -1) {
        checkedProjectIds.splice(i, 1);
      }
    }

    if (checkedProjectIds.length > 0) {
      $('.bulk-action').prop("disabled",false).trigger('chosen:updated');
    }
    else {
      $('.bulk-action').prop("disabled",true).trigger('chosen:updated');
    }
  });

  $('#bulk-delete').click(function(){
    bulkOperation("delete",  null);
  });

  $('select.bulk-action').chosen().change( function (evt, params) {
    var op = $(this).prop('id').substring(5);
    bulkOperation(op, params.selected);
  });

  $('#owner-filter, #close-date-filter').change( function () {
    var params = {};
    if ($('#owner-filter').val()) {
      params.owner = $('#owner-filter').val();
    }
    if ($('#close-date-filter').val()) {
      params.close_date = $('#close-date-filter').val();
    }
    window.location.search = $.param(params);
  });

  $('.filter-group, .bulk-group').hover(function(){
    $('.chosen-container-single').css('cursor', 'pointer');
    $('.chosen-single').css('cursor', 'pointer');
  });
});

function bulkOperation (operation, value) {
  var temp = {
    project_ids: checkedProjectIds,
    operation: operation,
    value: value
  };

  var data = $.param(temp);

  $.post("/project_bulk", data, 'json')
    .done(function () {
      window.location.replace(document.location.href); // reload page, keep filter params
    })
    .fail(function () {
      console.log("bulk error");
    });
}

function toggleSection(toggleSectionParentDOMObj) {
    if (toggleSectionParentDOMObj) {
        toggleSectionParentDOMObj.find(".toggle-icon").toggleClass("fa-caret-right fa-caret-down");
        toggleSectionParentDOMObj.next().next().toggle(400);
    }
};

// Copied from notifications.js for displaying notifications per project

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

/*
    Similar to large_number_to_human except it keeps a certain number of significant digits and discards the rest (always rounds down)
    large_number_to_human_signif_digits(9);        // 9
    large_number_to_human_signif_digits(99);       // 99
    large_number_to_human_signif_digits(199.9);    // 199
    large_number_to_human_signif_digits(1099.9);   // 1.09K
    large_number_to_human_signif_digits(11190);    // 11.1K
    large_number_to_human_signif_digits(103900);   // 103K
    large_number_to_human_signif_digits(104000);   // 104K
    large_number_to_human_signif_digits(104900);   // 104K
    large_number_to_human_signif_digits(1014900);  // 1.01M
*/
function large_number_to_human_signif_digits(number, significant_digits) {
  if (!significant_digits)
    significant_digits = 3;
  if (significant_digits < 0)
    significant_digits = 1;

  if (number == 0 || Math.abs(number) < 1) return 0;
  if (!number || Math.abs(number) > 100000000000000000000000000) return; // 10^24

  var sign = (number < 0) ? "-" : "";
  number = Math.abs(number);
  var s = ['','K', 'M', 'B', 'T', 'Quad', 'Quint', 'Sext', 'Sept'];
  var e = Math.floor(Math.log(number) / Math.log(1000));
  number = truncPrecision(number, significant_digits);
  return sign + (number / Math.pow(1000, e) + "" + s[e]);
}
// currently truncates by transforming into a string, removing the decimal point, taking a substring, then putting the decimal point back in the right place
function truncPrecision(number, significant_digits) {
  var number_str = number + "";
  var decimal_pos = number_str.search("\\.");
  var number_str_transform = number_str.replace(".","");  // remove the decimal pt
  number_str_transform = number_str_transform.substring(0, significant_digits);  // truncate to significant_digits digits

  if (decimal_pos >= 0 && decimal_pos <= 3) {
    return Number(number_str_transform.substring(0,decimal_pos) + "." + number_str_transform.substring(decimal_pos,number_str_transform.length));
  } else {
    var factor_adjust = (decimal_pos >= 0 ? decimal_pos : number_str.length) - significant_digits;
    return number_str_transform * Math.pow(10, factor_adjust);
  }
}
