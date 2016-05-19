jQuery(document).ready(function($) {

	$('.switch').on('click', function(e) {    
	    var trigger = $(this);
	 
	    if ( !trigger.hasClass('active') ) {
	      $('#loader').find('.loader-icon').addClass('hidden').filter('[data-cog*="' +  trigger.data('trigger') + '"]').removeClass('hidden');
	      trigger.addClass('active').siblings('.active').removeClass('active'); 
	    }
	    e.preventDefault();
	  });

	$('.start_date_datepicker').datepicker({
	  keyboardNavigation: false,
	  todayHighlight: true,
	  autoclose: true
	});


  //DataTables
  $('#projects-table').DataTable( {
    responsive: true,
    columnDefs: [
      { searchable: false, targets: [0,5,6,7,8,9]},
      { orderable: false, targets: [0,4,5,6,8,9] }
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

  /* Rendering object for defining how search-subs and member-search displays search results */
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

  /* Selectize for autocompleting possible subscribers */
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

  $("#search-account-projects").chosen()


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
    bulkOperation("delete",  null, "/project_bulk");
    window.location.replace("/projects");
  });

  $('.category_box').chosen({ disable_search: true, allow_single_deselect: true});
  $('.category_box').on('change',function(evt,params){
      bulkOperation("category",  params["selected"], "/project_bulk");
      window.location.replace("/projects");     
  });

  $('.owner_box').chosen({ allow_single_deselect: true});
  $('.owner_box').on('change',function(evt,params){
      bulkOperation("owner",  params["selected"], "/project_bulk");
      window.location.replace("/projects");     
  });


  $('.category_filter').chosen({ disable_search: true, allow_single_deselect: true});
  $('.category_filter').on('change',function(evt,params){
    var taskType="";
    if(params){
        window.location.replace("/projects?type="+params["selected"]);    
    }
    else{
      window.location.replace("/projects");
    }
  });

});


var checkCounter = 0;

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
  $.ajax({
      type: "POST",
      url: url,
      contentType: 'application/json',
      dataType: 'json',
      data: msg
  });
}


