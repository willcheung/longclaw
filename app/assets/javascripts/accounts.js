
$(document).ready(function(){
  //DataTables
  $('#accounts-table').DataTable( {
    responsive: true,
    columnDefs: [
      { searchable: false, targets: [0,4,5]},
      { orderable: false, targets: [0] }
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


  $('.bulk-account').change(function(){
    if($(this).is(":checked")){
      checkCounter++;
    }
    else{
      checkCounter--;
    }

    if(checkCounter>0)
    {
      $('#bulk-delete').prop("disabled",false);
      $('#bulk-owner').prop("disabled",false).trigger("chosen:updated");
      $('#bulk-type').prop("disabled",false).trigger("chosen:updated");
    }
    else
    {
      $('#bulk-delete').prop("disabled",true);
      $('#bulk-owner').prop("disabled",true).trigger("chosen:updated");
      $('#bulk-type').prop("disabled",true).trigger("chosen:updated");
    }
    // console.log(checkCounter);

  });

  $('#bulk-delete').click(function(){
      bulkOperation("delete",  null, "/account_bulk");
      window.location.replace("/accounts");
  });

  $('.category_box').chosen({ disable_search: true, allow_single_deselect: true});
  $('.category_box').on('change',function(evt,params){
      bulkOperation("category",  params["selected"], "/account_bulk");
      window.location.replace("/accounts");     
  });

  $('.owner_box').chosen({ allow_single_deselect: true});
  $('.owner_box').on('change',function(evt,params){
      bulkOperation("owner",  params["selected"], "/account_bulk");
      window.location.replace("/accounts");     
  });


  $('.category_filter').chosen({ disable_search: true, allow_single_deselect: true});
  $('.category_filter').on('change',function(evt,params){
    var taskType="";
    if(params){
        window.location.replace("/accounts?type="+params["selected"]);    
    }
    else{
      window.location.replace("/accounts");
    }
  });

  $('.filter-group, .bulk-group').hover(function(){
    $('.chosen-container-single').css('cursor', 'pointer');
    $('.chosen-single').css('cursor', 'pointer'); 
  });


});


var checkCounter = 0;


function bulkOperation(operation, value, url){
  var array = [];
  var i = 0;
  $('.bulk-account:checked').each(function(){
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
  $.ajax({
      type: "POST",
      url: url,
      contentType: 'application/json',
      dataType: 'json',
      data: msg
  });
}

