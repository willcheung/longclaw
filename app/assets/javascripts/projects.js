//= require highcharts-sparkline/highcharts-sparkline.js

var checkedProjectIds = [];
var URL_PREFIX = "/projects";

$('[data-toggle="tooltip"]').tooltip();

$(document).ready(function($) {

  $("#search-account-projects").chosen();
  $('#bulk-category').chosen({ disable_search: true, allow_single_deselect: true});
  $('#bulk-owner').chosen({ allow_single_deselect: true});
  $('#bulk-status').chosen({ disable_search: true, allow_single_deselect: true});
  $('.category_filter').chosen({ disable_search: true, allow_single_deselect: true, search_contains: true });

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
      { searchable: false, targets: [0,4,5,6,7,8,9,10,11] },
      { orderable: false, targets: [0,4,5,6,7,8,9,10,11] }
    ],
    "order": [[ 1, "asc" ]],
    "lengthMenu": [[50, 100, -1], [50, 100, "All"]],
    "dom":' <"col-sm-4 row"f><"top">rt<"col-sm-5"l><"col-sm-5"p><"bottom"i><"clear">',
    "language": {
      search: "_INPUT_",
      searchPlaceholder: "Start typing to filter list..."
    },
    bServerSide: true,
    fnServerParams: function (aoData) {
      if ($('#owner-filter').val()) {
        aoData.push({ name: 'owner', value: $('#owner-filter').val() });
      }
      if ($('#close-date-filter').val()) {
        aoData.push({ name: 'close_date', value: $('#close-date-filter').val() });
      }
      var stageSelection = $('#stage-chart').highcharts().getSelectedPoints();
      if (stageSelection.length !== 0) {
        aoData.push({ name: 'stage', value: getSelectedStages() })
      }
    },
    sAjaxSource: $('#projects-table').data('source'),
    fnDrawCallback: function (oSettings, json) {
      // console.log('fnDrawCallback')
      // console.log(oSettings)
      // console.log(json)
      initSparklines();
      $('[data-toggle="tooltip"]').tooltip();
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

  $('#close-date-filter').change( function () {
    setFilterParamsAndReloadPage();
  });

  $('#multiselect-filter-form').on("submit", function() {
    setFilterParamsAndReloadPage();
    return false;
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

function initSparklines() {
  // highcharts('SparkLine') options declared in highcharts-sparkline.js
  // original of initSparklines from highcharts-sparkline.js as well
  var start = +new Date(),
    $tds = $('div[data-sparkline]'),
    fullLen = $tds.length,
    n = 0;

// Creating 153 sparkline charts is quite fast in modern browsers, but IE8 and mobile
// can take some seconds, so we split the input into chunks and apply them in timeouts
// in order avoid locking up the browser process and allow interaction.
  function doChunk() {
    var time = +new Date(),
      i,
      len = $tds.length,
      $td,
      stringdata,
      arr,
      data,
      chart;

    for (i = 0; i < len; i += 1) {
      $td = $($tds[i]);
      stringdata = $td.data('sparkline');
      arr = stringdata.split('; ');
      data = $.map(arr[0].split(', '), parseFloat);
      chart = {};

      if (arr[1]) {
        chart.type = arr[1];
      }
      $td.highcharts('SparkLine', {
        series: [{
          data: data,
          pointStart: 1
        }],
        tooltip: {
          headerFormat: null,
          pointFormat: "<b>{point.y}</b>"
        },
        chart: chart
      });

      n += 1;

      // If the process takes too much time, run a timeout to allow interaction with the browser
      if (new Date() - time > 500) {
        $tds.splice(0, i + 1);
        setTimeout(doChunk, 0);
        break;
      }
    }
  }
  doChunk();

}

function setFilterParamsAndReloadPage() {
  let params = {};
  params.type = $('#type-filter').val() ? $('#type-filter').val() : "";
  params.owner = $('#owner-filter').val() ? $('#owner-filter').val() : "";
  params.close_date = $('#close-date-filter').val() ? $('#close-date-filter').val() : "Any";
  params.stage = getSelectedStages();
  // if (!$.isEmptyObject(params))
  //   console.log( "$.param(params)=" + $.param(params));

  window.location.search = $.param(params);
};

function getSelectedStages() {
  let stageSelection = $('#stage-chart').highcharts().getSelectedPoints();
  let stages_arr = [];
  for (var i=0; i < stageSelection.length; i++) {
    stages_arr.push(stageSelection[i].category)
  }
  if (stages_arr.length == 0)
    return ['Any'];
  else
    return stages_arr;
}

function resetStagesFilter() {
  let stageSelection = $('#stage-chart').highcharts().getSelectedPoints();
  for (var i=0; i < stageSelection.length; i++) {
    stageSelection[i].select(false); // de-select
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
