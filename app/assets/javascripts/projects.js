var checkCounter = 0;
var URL_PREFIX = "/projects";

jQuery(document).ready(function($) {

  $("#search-account-projects").chosen();
  $('.category_box').chosen({ disable_search: true, allow_single_deselect: true});
  $('.owner_box').chosen({ allow_single_deselect: true});
  $('.category_filter').chosen({ disable_search: true, allow_single_deselect: true});
  $('.owner_filter').chosen({ disable_search: true, allow_single_deselect: true});

	$('.switch').on('click', function(e) {
	    var trigger = $(this);

	    if ( !trigger.hasClass('active') ) {
	      $('#loader').find('.loader-icon').addClass('hidden').filter('[data-cog*="' +  trigger.data('trigger') + '"]').removeClass('hidden');
	      trigger.addClass('active').siblings('.active').removeClass('active');
	    }
	    e.preventDefault();
	  });


  //DataTables
  $('#projects-table').DataTable( {
    responsive: true,
    columnDefs: [
      { searchable: false, targets: [0,4,5,6,7,8,9,10,11,12]},
      { orderable: false, targets: [0,4,5,9,11,12] }
    ],
    "order": [[ 1, "asc" ]],
    "lengthMenu": [[50, 100, -1], [50, 100, "All"]],
    "dom":' <"col-sm-4 row"f><"top">rt<"col-sm-5"l><"col-sm-5"p><"bottom"i><"clear">',
    "language": {
      search: "_INPUT_",
      searchPlaceholder: "Start typing to filter list..."
    }
  } );

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


  /* Handle bulk action */
  $('.bulk-project').change(function(){
    if($(this).is(":checked")){
      checkCounter++;
    }
    else{
      checkCounter--;
    }

    if(checkCounter>0)
    {
      // $('.bulk-group').css('visibility','visible');
      $('#bulk-delete').prop("disabled",false);
      $('#bulk-owner').prop("disabled",false).trigger("chosen:updated");
      $('#bulk-type').prop("disabled",false).trigger("chosen:updated");
    }
    else
    {
      // $('.bulk-group').css('visibility','hidden');
      $('#bulk-delete').prop("disabled",true);
      $('#bulk-owner').prop("disabled",true).trigger("chosen:updated");
      $('#bulk-type').prop("disabled",true).trigger("chosen:updated");
    }
    // console.log(checkCounter);

  });

  $('#bulk-delete').click(function(){
    if(bulkOperation("delete",  null, "/project_bulk")==true){
      window.location.replace(URL_PREFIX);
    }
    else{
      console.log("bulk error");
    }
  });

  $('.category_box').on('change',function(evt,params){
      if(bulkOperation("category",  params["selected"], "/project_bulk")==true){
        window.location.replace(URL_PREFIX);
      }
      else{
        console.log("bulk error");
      }
  });

  $('.owner_box').on('change',function(evt,params){
      if(bulkOperation("owner",  params["selected"], "/project_bulk")==true){
        window.location.replace(URL_PREFIX);
      }
      else{
        console.log("bulk error");
      }
  });


  $('.category_filter').on('change',function(evt, params){
    var taskType = "";

    if (params) {
        taskType = "type=" + params["selected"];
    }

    newURL(window.location.search, "type", taskType);
  });
  
  $('.owner_filter').on('change',function(evt, params){
    var taskType = "";

    if (params) {
        taskType = "owner=" + params["selected"];
    }

    newURL(window.location.search, "owner", taskType);
  });

  $('.filter-group, .bulk-group').hover(function(){
    $('.chosen-container-single').css('cursor', 'pointer');
    $('.chosen-single').css('cursor', 'pointer');
  });
});

// Takes the query string and removes a parameter matching 'paramStr', retaining all other params
function removeParam(queryStr, paramStr) {
    if (queryStr.length == 0) return queryStr;

    var params = queryStr.split("&");
    var result = "";

    for (i = 0; i < params.length; i++){
        var param = params[i].split("=");
        if(param[0].length > 0 && param[0] !== paramStr){ //don't include if we find param
            result += params[i] + "&";
        }
    }

    if (result[result.length-1] === "&") 
        return result.substring(0, result.length-1);
    else 
        return result;

}

// Sets the browser URL with modified querystring when jQuery detects a change in the filter criteria
//   e.g., newURL(window.location.search, "type", "type=Other");
function newURL(fullQueryStr, changedParamStr, newParamValueStr) {
    var finalURL  = "";
    var newsearch = "";
    
    // always remove ampersand (&) in the front(?) or it will cause an error
    newQueryString = removeParam(fullQueryStr.substring(1), changedParamStr);

    if (newQueryString.length == 0){   
        newsearch = newParamValueStr;
    }
    else{
        if(newParamValueStr.length == 0){ // when user presses X, newParamValueStr is ""
            newsearch = newQueryString;
        }
        else{
            newsearch = newQueryString + "&" + newParamValueStr;
        }
    }

    if (newsearch.length == 0){
        finalURL = URL_PREFIX;
    }
    else{
        finalURL = URL_PREFIX + "/?" + newsearch;
    }

    window.location.replace(finalURL);
}

function bulkOperation(operation, value, url){
  var array = [];
  var i = 0;
  $('.bulk-project:checked').each(function(){
    array[i] = $(this).val();
    i++;
  });

  var temp = {
    selected: array,
    operation: operation,
    value: value
  };

  msg= JSON.stringify(temp);
  // console.log(msg);

  var result = false;

  $.ajax({
      type: "POST",
      url: url,
      contentType: 'application/json',
      dataType: 'json',
      data: msg,
      async: false,
      success: function(){
        // alert("success!");
        result = true;
      },
      error: function(){
        // alert("bulk error");
        result = false;
      }
  });

  return result;
}

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
