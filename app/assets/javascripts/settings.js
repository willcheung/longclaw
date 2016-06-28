$(document).ready(function() {
    $('#users-table').DataTable( {
        "scrollX": true,
        "responsive": true,
        "order": [[5, "desc"]],
        "bPaginate": false,
        "dom":' <"col-sm-4 row"f><"top">rt<"col-sm-5"l><"col-sm-5"p><"bottom"i><"clear">',
        "language": {
		      search: "_INPUT_",
		      searchPlaceholder: "Start typing to filter list..."
		    }
    } );
    
    $('input[type=search]').attr('size', '50');

    $('.salesforce_account_box').chosen({allow_single_deselect: true});

    $('.salesforce_account_box').on('change',function(evt,params){
        console.log($(this).attr('id'));
        console.log(params);   

        // $.ajax({url:'/notifications/'+$(this).attr('id')+'/update_is_complete'});

    if(params){
      $.ajax({url:'/update_salesforce/?id='+$(this).attr('id')+'&sid='+params["selected"]});
    }
    else{
      $.ajax({url:'/update_salesforce/?id='+$(this).attr('id')+'&sid= '});
    }

    })
} );