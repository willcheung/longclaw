var checkedAccountIds = [];
var URL_PREFIX = "/accounts";
$('[data-toggle="tooltip"]').tooltip();

$(document).ready(function(){
  
  $('#bulk-category').chosen({ disable_search: true, allow_single_deselect: true});
  $('#bulk-owner').chosen({ allow_single_deselect: true});
  
  $('.category_filter').chosen({ disable_search: true, allow_single_deselect: true});
  $('.owner_filter').chosen({ disable_search: true, allow_single_deselect: true});

  //DataTables
  $('#accounts-table').DataTable({
    responsive: true,
    columnDefs: [
      { searchable: false, targets: [0,3,4,5,6]},
      { orderable: false, targets: [0,3,4,5,6] }
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
      if ($('.category_filter').val()) {
        aoData.push({ name: 'account_type', value: $('.category_filter').val() });
      }
      if ($('.owner-filter').val()) {
        aoData.push({ name: 'owner', value: $('.owner-filter').val() });
      }
    },
    sAjaxSource: $('#accounts-table').data('source')
  });

  $('input[type=search]').attr('size', '50');

  $('.filter-group, .bulk-group').hover(function(){
    $('.chosen-container-single').css('cursor', 'pointer');
    $('.chosen-single').css('cursor', 'pointer'); 
  });

  /* Handle bulk action */
  $('#accounts-table tbody').on('change', '.bulk-account', function () {
    if ($(this).prop("checked")) {
      checkedAccountIds.push($(this).val());
    }
    else {
      var i = checkedAccountIds.indexOf($(this).val());
      if (i !== -1) {
        checkedAccountIds.splice(i, 1);
      }
    }

    if (checkedAccountIds.length > 0) {
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

  /*$('.category_filter').on('change',function(evt,params){
    var taskType="";
    if(params){
        window.location.replace("/accounts?account_type="+params["selected"]);    
    }
    else if(typeof(params) == 'undefined') {
      taskType = "none";
      window.location.replace("/accounts?account_type="+taskType);  
    }
    else{
      window.location.replace("/accounts");
    }
  });*/

  $('.category_filter').on('change',function(evt, params){
    var taskType = "";

    if (params) {
        taskType = "account_type=" + params["selected"];
    }
     if (typeof(params) == 'undefined') {
      taskType = "account_type=" + "none";
    }

    newURL(window.location.search, "account_type", taskType);
  });

  $('.owner_filter').on('change',function(evt, params){
    var taskType = "";

    if (params) {
        taskType = "owner=" + params["selected"];
    }
    if (typeof(params) == 'undefined') {
      taskType = "owner=" + 0;
    }


    newURL(window.location.search, "owner", taskType);
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


function bulkOperation (operation, value) {
  var temp = {
    account_ids: checkedAccountIds,
    operation: operation,
    value: value
  };

  var data = $.param(temp);

  $.post("/account_bulk", data, 'json')
    .done(function () {
      window.location.replace(document.location.href); // reload page, keep filter params
    })
    .fail(function () {
      console.log("bulk error");
    });
}